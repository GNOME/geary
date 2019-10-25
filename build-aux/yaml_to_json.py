#!/usr/bin/env python3

import json
import os
import sys
import yaml

def main(input_path, source_path, output_path):
    with open(input_path) as input:
        obj = yaml.safe_load(input)

    comment = '/* Automatically generated from {}, do not modify. */'.format(
        os.path.basename(input_path)
    )
    source_output_path = os.path.join(
        source_path, os.path.basename(output_path)
    )
    for path in [output_path, source_output_path]:
        with open(path, 'w') as output:
            print(comment, file=output)
            json.dump(obj, output, indent=4)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3])
