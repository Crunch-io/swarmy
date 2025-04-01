#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
from setuptools import setup, find_packages

# Get project directory and name
thisdir = os.path.abspath(os.path.dirname(__file__))
projName = 'swarmy'

# Read version (Python 3 text mode)
with open(os.path.join(thisdir, 'version.txt'), 'r') as f:
    version = f.read().strip()

# Write version to _version.py (Python 3 text mode)
with open(os.path.join(thisdir, projName, '_version.py'), 'w') as out:
    out.write(f'version = "{version}"\n')  # f-string (Python 3.6+)

def get_long_desc():
    root_dir = os.path.dirname(__file__) or '.'
    with open(os.path.join(root_dir, 'README.md'), 'r', encoding='utf-8') as f:
        return f.read()

testing_extras = []

setup(
    name=projName,
    version=version,
    description="AWS Autoscaling and Metadata utilities",
    long_description=get_long_desc(),
    long_description_content_type='text/markdown',  # Required for PyPI markdown
    url='https://github.com/Crunch-io/swarmy',
    download_url='https://github.com/Crunch-io/crunch-lib/archive/master.zip',
    classifiers=[
        "Programming Language :: Python :: 3",
        "Topic :: Software Development :: Libraries :: Python Modules",
    ],
    author='Crunch.io',
    author_email='dev@crunch.io',
    license='MIT',
    install_requires=[
        'awscli',
        'boto',
        'docopt',
    ],
    packages=find_packages(),
    include_package_data=True,
    package_data={
        'swarmy': ['*.json', '*.csv']
    },
    zip_safe=True,
    extras_require={
        'testing': testing_extras,
    },
    entry_points={
        'console_scripts': [
            "dynamic_hostname = swarmy.dynamic_hostname:main",
        ]
    },
)
