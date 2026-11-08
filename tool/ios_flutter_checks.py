"""Run the complete iPhone host regression selection with Flutter suite sharding."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'tool/ios_flutter_tests.txt'


def command(shard, shards, manifest=MANIFEST):
    if shards < 1 or not 0 <= shard < shards:
        raise ValueError('Shard index must be within the positive shard count')
    selected = [line.strip() for line in manifest.read_text().splitlines()
                if line.strip() and not line.lstrip().startswith('#')]
    if not selected:
        raise ValueError('The iOS test selection must be nonempty')
    expanded = []
    for name in selected:
        path = Path(name)
        if path.parts[0] != 'test' or '..' in path.parts:
            raise ValueError('Invalid iOS regression path: ' + name)
        matches = sorted(ROOT.glob(name))
        if not matches:
            raise ValueError('Missing iOS regression path: ' + name)
        expanded.extend(str(match.relative_to(ROOT)) for match in matches)
    selected = list(dict.fromkeys(expanded))
    return ['flutter', 'test', '--no-pub', '--total-shards', str(shards),
            '--shard-index', str(shard), *selected]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--shards', type=int, default=1)
    parser.add_argument('--shard', type=int, default=0)
    args = parser.parse_args()
    subprocess.run(command(args.shard, args.shards), cwd=ROOT, check=True)
