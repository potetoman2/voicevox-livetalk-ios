"""Use embedded policy text as the website body; never execute its markup."""
import argparse, html, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def sync(check=False):
    for name in ('privacy', 'terms'):
        text = (ROOT / f'shared/{name}.txt').read_text(encoding='utf-8')
        site = ROOT / f'site/{name}.html'
        current = site.read_text(encoding='utf-8')
        updated, count = re.subn(r'(<div class="card document">).*?(</div></main>)',
            lambda m: m[1] + html.escape(text) + m[2], current, flags=re.S)
        if count != 1:
            raise ValueError(f'Expected one policy container: {name}')
        if check and updated != current:
            raise ValueError(f'App and website policy differ: {name}; run scripts/sync_policies.py')
        if not check:
            site.write_text(updated, encoding='utf-8')
    print('Embedded and website policies match' if check else 'Updated website policies from embedded text')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--check', action='store_true')
    sync(parser.parse_args().check)
