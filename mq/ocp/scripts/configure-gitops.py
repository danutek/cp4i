#!/usr/bin/env python3
"""Set public Git coordinates and the GitOps controller identity across bootstrap manifests."""
import argparse
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit
import yaml

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo-url', required=True, help='Repository URL without credentials')
parser.add_argument('--repository-root', default='mq/ocp', help='Path in Git; use an empty string for a standalone repository')
parser.add_argument('--revision', default='main')
parser.add_argument('--argocd-namespace', default='openshift-gitops')
parser.add_argument('--controller-service-account', default='openshift-gitops-argocd-application-controller')
args = parser.parse_args()
if not args.repo_url.startswith(('https://', 'ssh://', 'git@')):
    parser.error('Use an HTTPS or SSH Git URL.')
if urlsplit(args.repo_url).password is not None:
    parser.error('Keep repository credentials in Argo CD Secrets, not repository URLs.')
repository_root = args.repository_root.strip('/')
if args.repository_root.startswith('/') or '..' in PurePosixPath(repository_root).parts:
    parser.error('repository-root must be a relative Git path without parent traversal.')

def gitpath(path):
    return f'{repository_root}/{path}' if repository_root else path

def load(path):
    return yaml.safe_load((ROOT / path).read_text())

def save(path, data):
    (ROOT / path).write_text(yaml.safe_dump(data, sort_keys=False))

project = load('operations/master/base/project.yaml')
project['metadata']['namespace'] = args.argocd_namespace
project['spec']['sourceRepos'] = [args.repo_url]
save('operations/master/base/project.yaml', project)
appset = load('operations/master/base/applicationset.yaml')
appset['metadata']['namespace'] = args.argocd_namespace
appset['spec']['generators'][0]['git'].update(repoURL=args.repo_url, revision=args.revision)
appset['spec']['generators'][0]['git']['directories'][0]['path'] = gitpath('workloads/mqm/*/overlays/dev/cus')
appset['spec']['template']['spec']['source'].update(repoURL=args.repo_url, targetRevision=args.revision)
save('operations/master/base/applicationset.yaml', appset)
for env in ['dev', 'test', 'qa', 'perf', 'prod']:
    path = f'operations/master/overlays/{env}/cus/kustomization.yaml'
    overlay = load(path)
    for patch in overlay['patches']:
        if patch['target']['kind'] == 'ApplicationSet':
            operations = yaml.safe_load(patch['patch'])
            for operation in operations:
                if operation['path'] == '/spec/generators/0/git/directories/0/path':
                    operation['value'] = gitpath(f'workloads/mqm/*/overlays/{env}/cus')
            patch['patch'] = yaml.safe_dump(operations, sort_keys=False)
    save(path, overlay)
    path = f'bootstrap/{env}-cus.yaml'
    application = load(path)
    application['metadata']['namespace'] = args.argocd_namespace
    application['spec']['source'].update(repoURL=args.repo_url, targetRevision=args.revision,
                                       path=gitpath(f'operations/master/overlays/{env}/cus'))
    application['spec']['destination']['namespace'] = args.argocd_namespace
    save(path, application)
    path = f'platform/namespaces/{env}/namespace-rbac.yaml'
    documents = list(yaml.safe_load_all((ROOT / path).read_text()))
    for document in documents:
        if document['kind'] == 'Namespace':
            document['metadata']['labels']['argocd.argoproj.io/managed-by'] = args.argocd_namespace
        if document['kind'] == 'RoleBinding':
            document['subjects'][0].update(name=args.controller_service_account, namespace=args.argocd_namespace)
    (ROOT / path).write_text(yaml.safe_dump_all(documents, sort_keys=False))
platform = load('bootstrap/platform.yaml')
platform['metadata']['namespace'] = args.argocd_namespace
platform['spec']['source'].update(repoURL=args.repo_url, targetRevision=args.revision, path=gitpath('platform'))
save('bootstrap/platform.yaml', platform)
print('Updated Git coordinates and controller bindings. Review and commit these public configuration changes.')
