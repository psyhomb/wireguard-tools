#!/usr/bin/env python3
# Author: Milos Buncic
# Date: 2020/06/10
# Description: Generate main configuration file (hooks.json) for webhook service

import os
import sys
import json

# Webhook working directory
WH_DIR = '/etc/webhook'
# Webhook configuration file
WH_CONFIG = '{}/hooks.json'.format(WH_DIR)


def writefile(filename, text):
  """ Write JSON object to file """
  try:
    with open(filename, 'w') as f:
      f.write(json.dumps(text, indent=2, ensure_ascii=False, sort_keys=True))
      f.write('\n')
  except IOError:
    print('Error while writing to file')


def readfile(filename):
  """ Read JSON from file and return dict """
  try:
    with open(filename, 'r') as f:
      return json.load(f)
  except IOError:
    print('Error while reading from file')


def main():
  main_file = '{}/main.json'.format(WH_DIR)
  if not os.path.isfile(main_file):
    print('{} file does not exist!'.format(main_file))
    sys.exit(1)

  mf = readfile(main_file)

  files = os.listdir(WH_DIR)
  l = []
  for f in files:
    auth_file = '{}/{}'.format(WH_DIR, f)
    if f == 'main.json' or f == 'hooks.json' or os.path.isdir(auth_file) or os.path.splitext(auth_file)[1] != '.json':
      continue

    l.append(readfile(auth_file))

  for i in range(0, len(mf)):
    mf[i]['trigger-rule']['or'] = l

  writefile(WH_CONFIG, mf)


if __name__ == '__main__':
    main()
