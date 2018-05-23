#!/usr/bin/env python3

import re
import sys
import subprocess

try:
  version = subprocess.check_output(
    ['git', 'describe', '--all', '--long', '--dirty'],
    stderr=subprocess.DEVNULL
  )
except:
  sys.exit(1)

version = str(version, encoding='UTF-8').strip()
print(re.sub(r'^heads\/(.*)-0-(g.*)$', r'\1~\2', version))
