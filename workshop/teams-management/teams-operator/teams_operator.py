#!/usr/bin/env python3
"""
Teams Operator - Creates Kubernetes namespaces when teams are created in the Teams API
"""

import asyncio
import json
import logging
import os
import time
from typing import Set, Dict, Any, Optional
import aiohttp
from kubernetes import client, config
from kubernetes.client.rest import ApiException

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('teams-operator')

class TeamsOperator:
    def __init__(self):
        self.teams_api_url = os.getenv('TEAMS_API_URL', 'http://teams-api-service:80')
        self.poll_interval = int(os.getenv('POLL_INTERVAL', '30'))  # seconds
        self.known_teams: Set[str] = set()
        self.team_namespaces: Dict[str, str] = {}
        
        # Initialize Kubernetes client
        try:
            # Try in-cluster config first (when running in pod)
            config.load_incluster_config()
            logger.info("Loaded in-cluster Kubernetes config")
        except config.ConfigException:
            # Fall back to local kubeconfig (for development)
            config.load_kube_config()
            logger.info("Loaded local kubeconfig")
        
        self.k8s_core_v1 = client.CoreV1Api()
        
    def sanitize_namespace_name(self, team_name: str) -> str:
        """Convert team name to valid Kubernetes namespace name"""
        # Lowercase, replace spaces/special chars with hyphens, remove consecutive hyphens
        namespace = team_name.lower()
        namespace = ''.join(c if c.isalnum() else '-' for c in namespace)
        namespace = '-'.join(filter(None, namespace.split('-')))  # Remove consecutive hyphens
        
        # Ensure it starts and ends with alphanumeric
        namespace = namespace.strip('-')
        
        # Kubernetes namespace names must be <= 63 characters
        if len(namespace) > 63:
            namespace = namespace[:63].rstrip('-')
            
        # Add prefix to avoid conflicts
        namespace = f"team-{namespace}"
        
        return namespace
    
    async def fetch_teams(self) -> list:
        """Fetch current teams from the Teams API"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.teams_api_url}/teams") as response:
                    if response.status == 200:
                        teams = await response.json()
                        logger.debug(f"Fetched {len(teams)} teams from API")
                        return teams
                    else:
                        logger.error(f"Failed to fetch teams: HTTP {response.status}")
                        return []
        except aiohttp.ClientError as e:
            logger.error(f"Error connecting to Teams API: {e}")
            return []
        except Exception as e:
            logger.error(f"Unexpected error fetching teams: {e}")
            return []

    def create_resource_quota(self, namespace_name: str, team_id: str, team_name: str, extra_labels: Optional[Dict[str, str]] = None, extra_annotations: Optional[Dict[str, str]] = None) -> bool:
        """Create a default ResourceQuota inside the team namespace"""
        try:
            extra_labels = extra_labels or {}
            extra_annotations = extra_annotations or {}

            rq_body = client.V1ResourceQuota(
                metadata=client.V1ObjectMeta(
                    name="team-quota",
                    namespace=namespace_name,
                    labels={
                        "app.kubernetes.io/managed-by": "teams-operator",
                        "teams.example.com/team-id": team_id,
                        "teams.example.com/team-name": team_name.replace(" ", "-").lower(),
                        **extra_labels,
                    },
                    annotations={
                        "teams.example.com/created-by": "teams-operator",
                        "teams.example.com/team-id": team_id,
                        **extra_annotations,
                    },
                ),
                spec=client.V1ResourceQuotaSpec(
                    hard={
                        "pods": "10",
                        "requests.cpu": "1",
                        "requests.memory": "1Gi",
                        "limits.cpu": "2",
                        "limits.memory": "2Gi",
                    }
                ),
            )

            self.k8s_core_v1.create_namespaced_resource_quota(namespace=namespace_name, body=rq_body)
            logger.info(f"📦 Created ResourceQuota 'team-quota' in namespace '{namespace_name}'")
            return True
        except ApiException as e:
            if e.status == 409:
                logger.warning(f"⚠️ ResourceQuota 'team-quota' already exists in namespace '{namespace_name}'")
                return True
            logger.error(f"❌ Failed to create ResourceQuota in namespace '{namespace_name}': {e}")
            return False
        except Exception as e:
            logger.error(f"❌ Unexpected error creating ResourceQuota: {e}")
            return False
    
    def create_namespace(self, team_id: str, team_name: str, namespace_name: str, extra_labels: Optional[Dict[str, str]] = None, extra_annotations: Optional[Dict[str, str]] = None) -> bool:
        """Create a Kubernetes namespace for the team"""
        try:
            extra_labels = extra_labels or {}
            extra_annotations = extra_annotations or {}

            namespace_labels = {
                "app.kubernetes.io/managed-by": "teams-operator",
                "teams.example.com/team-id": team_id,
                "teams.example.com/team-name": team_name.replace(" ", "-").lower(),
                **extra_labels,
            }

            namespace_annotations = {
                "teams.example.com/original-team-name": team_name,
                "teams.example.com/created-by": "teams-operator",
                "teams.example.com/team-id": team_id,
                **extra_annotations,
            }

            # Define namespace metadata
            namespace_body = client.V1Namespace(
                metadata=client.V1ObjectMeta(
                    name=namespace_name,
                    labels=namespace_labels,
                    annotations=namespace_annotations,
                )
            )
            
            # Create the namespace
            self.k8s_core_v1.create_namespace(body=namespace_body)
            logger.info(f"✅ Created namespace '{namespace_name}' for team '{team_name}' (ID: {team_id})")
            return True
            
        except ApiException as e:
            if e.status == 409:  # Namespace already exists
                logger.warning(f"⚠️ Namespace '{namespace_name}' already exists")
                return True
            else:
                logger.error(f"❌ Failed to create namespace '{namespace_name}': {e}")
                return False
        except Exception as e:
            logger.error(f"❌ Unexpected error creating namespace: {e}")
            return False
    
    def delete_namespace(self, namespace_name: str, team_name: str) -> bool:
        """Delete a Kubernetes namespace when team is removed"""
        try:
            self.k8s_core_v1.delete_namespace(name=namespace_name)
            logger.info(f"🗑️ Deleted namespace '{namespace_name}' for removed team '{team_name}'")
            return True
        except ApiException as e:
            if e.status == 404:  # Namespace doesn't exist
                logger.warning(f"⚠️ Namespace '{namespace_name}' not found (already deleted?)")
                return True
            else:
                logger.error(f"❌ Failed to delete namespace '{namespace_name}': {e}")
                return False
        except Exception as e:
            logger.error(f"❌ Unexpected error deleting namespace: {e}")
            return False
    
    async def reconcile_teams(self):
        """Main reconciliation loop - sync teams with namespaces"""
        teams = await self.fetch_teams()
        current_teams = {team['id']: team for team in teams}
        current_team_ids = set(current_teams.keys())
        
        # Handle new teams (create namespaces)
        new_teams = current_team_ids - self.known_teams
        for team_id in new_teams:
            team = current_teams[team_id]
            team_name = team['name']
            namespace_name = team.get('namespace') or self.sanitize_namespace_name(team_name)

            extra_labels = team.get('labels') if isinstance(team.get('labels'), dict) else {}
            extra_annotations = team.get('annotations') if isinstance(team.get('annotations'), dict) else {}
            
            if self.create_namespace(team_id, team_name, namespace_name, extra_labels=extra_labels, extra_annotations=extra_annotations):
                self.create_resource_quota(namespace_name, team_id, team_name, extra_labels=extra_labels, extra_annotations=extra_annotations)
                self.team_namespaces[team_id] = namespace_name
        
        # Handle deleted teams (remove namespaces)
        deleted_teams = self.known_teams - current_team_ids
        for team_id in deleted_teams:
            if team_id in self.team_namespaces:
                namespace_name = self.team_namespaces[team_id]
                # Get team name from namespace annotations if possible
                team_name = f"team-{team_id}"  # fallback
                
                if self.delete_namespace(namespace_name, team_name):
                    del self.team_namespaces[team_id]
        
        # Update known teams
        self.known_teams = current_team_ids
        
        if new_teams or deleted_teams:
            logger.info(f"📊 Reconciliation complete: {len(current_teams)} teams, {len(self.team_namespaces)} namespaces")
    
    async def run(self):
        """Main operator loop"""
        logger.info(f"🚀 Teams Operator starting...")
        logger.info(f"📡 Teams API URL: {self.teams_api_url}")
        logger.info(f"⏰ Poll interval: {self.poll_interval} seconds")
        
        # Initial reconciliation
        await self.reconcile_teams()
        
        # Main loop
        while True:
            try:
                await asyncio.sleep(self.poll_interval)
                await self.reconcile_teams()
            except KeyboardInterrupt:
                logger.info("👋 Received shutdown signal, exiting...")
                break
            except Exception as e:
                logger.error(f"❌ Error in main loop: {e}")
                await asyncio.sleep(self.poll_interval)

async def main():
    """Entry point"""
    operator = TeamsOperator()
    await operator.run()

if __name__ == "__main__":
    asyncio.run(main())
