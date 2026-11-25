#!/usr/bin/env python3
"""Render and check every selected OCP overlay; optionally request API-server dry runs."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
import shutil
import subprocess
import sys
import yaml

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / 'k8s'
ENVIRONMENTS = ['dev', 'test', 'qa', 'perf', 'prod']
PROFILES = {
    'dev': ('500m', '512Mi', '1', '1Gi', '5Gi', '10Gi', '10Gi'),
    'test': ('500m', '1Gi', '1', '2Gi', '5Gi', '20Gi', '10Gi'),
    'qa': ('1', '2Gi', '2', '4Gi', '10Gi', '30Gi', '20Gi'),
    'perf': ('2', '4Gi', '4', '8Gi', '10Gi', '64Gi', '32Gi'),
    'prod': ('2', '4Gi', '4', '8Gi', '10Gi', '64Gi', '32Gi'),
}

def check(condition, message):
    if not condition:
        raise ValueError(message)

def cli():
    for tool in ('kustomize', 'oc', 'kubectl'):
        binary = shutil.which(tool)
        if binary:
            return [binary] if tool == 'kustomize' else [binary, 'kustomize']
    if Path('/usr/local/bin/oc').is_file():
        return ['/usr/local/bin/oc', 'kustomize']
    raise ValueError('Install kustomize or an oc/kubectl client with Kustomize support.')

def render(path):
    result = subprocess.run(cli() + [str(path)], capture_output=True, text=True, timeout=60)
    check(result.returncode == 0, f'{path}: {result.stderr.strip()}')
    return [doc for doc in yaml.safe_load_all(result.stdout) if doc]

def source_names():
    names = {}
    for folder in sorted((SOURCE / 'workloads/mqm').iterdir()):
        if not folder.is_dir():
            continue
        base = yaml.safe_load((folder / 'base/kustomization.yaml').read_text())
        statefulset_patch = yaml.safe_load(base['patches'][0]['patch'])
        env = statefulset_patch['spec']['template']['spec']['containers'][0]['env']
        names[folder.name] = next(item['value'] for item in env if item['name'] == 'MQ_QMGR_NAME')
    return names

def validate_operand(path, expected_name, deployment_ready):
    environment = path.parts[-2]
    documents = render(path)
    check({d['kind'] for d in documents} <= {'QueueManager', 'ConfigMap'}, f'{path}: Git owns an operator-generated resource')
    qms = [doc for doc in documents if doc['kind'] == 'QueueManager']
    check(len(qms) == 1, f'{path}: expected exactly one QueueManager')
    cr = qms[0]
    spec = cr['spec']
    qm = spec['queueManager']
    identity = cr['metadata']['name']
    check(qm['name'] == expected_name, f'{path}: logical MQ name differs from source')
    check(cr['metadata']['namespace'] == 'mq-ocp-' + environment, f'{path}: incorrect namespace')
    check(identity == path.parts[-4] + '-qm', f'{path}: unexpected CR resource name')
    check(spec['labels']['queueManagerIdentity'] == identity, f'{path}: pod identity label was not rewritten')
    expected_type = 'SingleInstance' if environment == 'dev' else 'NativeHA'
    check(qm['availability']['type'] == expected_type, f'{path}: incorrect topology')
    if environment != 'dev':
        check(qm['availability']['updateStrategy'] == 'RollingUpdate', f'{path}: operator rollout must be enabled')
        check(qm['availability']['tls']['secretName'], f'{path}: missing replication TLS')
        anti = spec['affinity']['podAntiAffinity']
        for term in anti['requiredDuringSchedulingIgnoredDuringExecution']:
            check(term['labelSelector']['matchLabels']['queueManagerIdentity'] == identity, f'{path}: wrong required-affinity identity')
        for term in anti['preferredDuringSchedulingIgnoredDuringExecution']:
            check(term['podAffinityTerm']['labelSelector']['matchLabels']['queueManagerIdentity'] == identity, f'{path}: wrong preferred-affinity identity')
        zones = [t for t in anti['requiredDuringSchedulingIgnoredDuringExecution'] if t['topologyKey'] == 'topology.kubernetes.io/zone']
        check(bool(zones) == (environment in ['perf', 'prod']), f'{path}: zone constraint differs from environment policy')
    cm = {doc['metadata']['name']: doc for doc in documents if doc['kind'] == 'ConfigMap'}
    selected = []
    for source in qm['mqsc']:
        if 'configMap' not in source:
            continue
        ref = source['configMap']
        check(ref['name'] in cm, f'{path}: stale/missing generated MQSC ConfigMap reference')
        check(re.search(r'-[a-z0-9]{10}$', ref['name']), f'{path}: MQSC content hash is missing')
        for item in ref['items']:
            check(item in cm[ref['name']]['data'], f'{path}: missing MQSC key')
            selected.append(cm[ref['name']]['data'][item])
    payload = '\n'.join(selected)
    check(('CHLAUTH(DISABLED)' in payload) == (environment == 'dev'), f'{path}: dev authentication bypass escaped into a higher environment')
    check(("MCAUSER('mqm')" in payload) == (environment == 'dev'), f'{path}: dev mqm mapping escaped into a higher environment')
    storage = qm['storage']
    check(storage['defaultDeleteClaim'] is False, f'{path}: PVC retention default changed')
    for volume in ['queueManager', 'persistedData', 'recoveryLogs']:
        check(storage[volume]['type'] == 'persistent-claim' and storage[volume]['deleteClaim'] is False, f'{path}: non-persistent or auto-deleted storage')
    cpu, memory, limit_cpu, limit_memory, qm_size, data_size, log_size = PROFILES[environment]
    check(qm['resources'] == {'requests': {'cpu': cpu, 'memory': memory}, 'limits': {'cpu': limit_cpu, 'memory': limit_memory}}, f'{path}: sizing mismatch')
    check([storage[k]['size'] for k in ['queueManager', 'persistedData', 'recoveryLogs']] == [qm_size, data_size, log_size], f'{path}: PVC sizing mismatch')
    check(spec['license']['use'] == ('Production' if environment == 'prod' else 'NonProduction'), f'{path}: incorrect license use')
    check('Prune=false' in cr['metadata']['annotations']['argocd.argoproj.io/sync-options'], f'{path}: CR prune guard absent')
    if deployment_ready:
        check(spec['license']['accept'] is True, f'{path}: accept the applicable IBM license before deployment')
    return path, documents

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--environment', choices=ENVIRONMENTS, action='append')
    parser.add_argument('--deployment-ready', action='store_true', help='Also require license.accept=true')
    parser.add_argument('--server-dry-run', action='store_true', help='Contact the configured cluster; requires prepared namespaces, CRDs and secrets')
    args = parser.parse_args()
    names = source_names()
    folders = {p.name for p in (ROOT / 'workloads/mqm').iterdir() if p.is_dir()}
    check(folders == set(names), 'Queue-manager directory set differs from mq/k8s')
    environments = args.environment or ENVIRONMENTS
    tasks = [(ROOT / f'workloads/mqm/{folder}/overlays/{environment}/cus', name) for folder, name in names.items() for environment in environments]
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda task: validate_operand(*task, args.deployment_ready), tasks))
    identities = set()
    for path, documents in results:
        for document in documents:
            key = (document['kind'], document['metadata'].get('namespace'), document['metadata']['name'])
            check(key not in identities, f'Duplicate resource identity: {key}')
            identities.add(key)
    for environment in environments:
        documents = render(ROOT / f'operations/master/overlays/{environment}/cus')
        project = next(d for d in documents if d['kind'] == 'AppProject')
        appset = next(d for d in documents if d['kind'] == 'ApplicationSet')
        template = appset['spec']['template']
        check(template['spec']['project'] == project['metadata']['name'], 'ApplicationSet project mismatch')
        check(template['spec']['destination']['namespace'] == 'mq-ocp-' + environment, 'ApplicationSet namespace mismatch')
        check(('automated' in template['spec']['syncPolicy']) == (environment == 'dev'), 'Non-dev auto-sync is enabled')
        check(appset['spec']['syncPolicy']['preserveResourcesOnDeletion'], 'ApplicationSet deletion preservation disabled')
        directory = appset['spec']['generators'][0]['git']['directories'][0]['path']
        check(directory.endswith(f'workloads/mqm/*/overlays/{environment}/cus'), 'Incorrect Git generator path')
        # The basename is the region; the QM is four segments from the end, for either Git root layout.
        example = directory.replace('*', sorted(names)[0])
        check(example.split('/')[-4] == sorted(names)[0], 'Application naming selects the wrong directory segment')
        check('sub (len .path.segments) 4' in template['metadata']['name'], 'Application naming is not root-depth independent')
    for path in (ROOT / 'platform/operator', ROOT / 'platform/namespaces'):
        render(path)
    if args.server_dry_run:
        oc = shutil.which('oc') or '/usr/local/bin/oc'
        for namespace in sorted({'mq-ocp-' + env for env in environments}):
            for secret in ['ibm-entitlement-key'] + ([] if namespace.endswith('-dev') else ['mq-nativeha-replication-tls']):
                result = subprocess.run([oc, 'get', 'secret', secret, '-n', namespace, '-o', 'name'], capture_output=True, text=True)
                check(result.returncode == 0, f'{namespace}: missing/unreadable required Secret {secret}')
        for path, documents in results:
            result = subprocess.run([oc, 'apply', '--dry-run=server', '--server-side', '-f', '-'], input=yaml.safe_dump_all(documents), capture_output=True, text=True)
            check(result.returncode == 0, f'{path}: API-server validation failed: {result.stderr.strip()}')
    print(f'PASS: {len(results)} operand overlays; {len(names)} matching logical queue managers; {len(environments)} GitOps roots; platform overlays.')
    print('Checked names, hashes/references, topology, placement, security selection, resources, PVC retention, and sync policies.')
    if not args.server_dry_run:
        print('Offline checks only: no cluster API/Operator admission validation or deployment was performed.')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, StopIteration, subprocess.SubprocessError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
