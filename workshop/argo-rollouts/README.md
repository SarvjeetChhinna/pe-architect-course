# Argo Rollouts

## Install

```bash
chmod +x install.sh
./install.sh
```

## Dashboard (kubectl plugin)

```bash
chmod +x dashboard.sh
./dashboard.sh
# open http://localhost:3100
```

If you don't have the plugin installed, install it with krew:

```bash
kubectl krew install argo-rollouts
```

## Demo Rollout

```bash
chmod +x demo/demo-apply.sh
./demo/demo-apply.sh

# Watch progress
kubectl get rollout -n rollouts-demo -w
```

## Cleanup

```bash
chmod +x demo/demo-cleanup.sh
./demo/demo-cleanup.sh
```

## Uninstall

```bash
chmod +x uninstall.sh
./uninstall.sh
```
