// src/app/models/team.model.ts
export interface Team {
  id: string;
  name: string;
  namespace: string;
  created_at: string;
  owner?: string;
  labels?: { [key: string]: string };
  annotations?: { [key: string]: string };
}

export interface TeamCreate {
  name: string;
  namespace?: string;
  owner?: string;
  labels?: { [key: string]: string };
  annotations?: { [key: string]: string };
}
