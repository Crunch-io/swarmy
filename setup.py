#!/usr/bin/env python
# coding: utf-8

import os
thisdir = os.path.abspath(os.path.dirname(__file__))
projName = 'swarmy'

from setuptools import setup, find_packages

version = open(os.path.join(thisdir, 'version.txt'), 'rb').read().strip()

#Write out the version to the _version.py file
with open(os.path.join(thisdir, projName, '_version.py'), 'wt') as out:
    out.write('version="%s"' % version)

def get_long_desc():
    root_dir = os.path.dirname(__file__)
    if not root_dir:
        root_dir = '.'
    return open(os.path.join(root_dir, 'README.md')).read()

testing_extras = []

setup(
    name=projName,
    version=version,
    description="AWS Autoscaling and Metadata utilities",
    long_description=get_long_desc(),
    url='https://github.com/Crunch-io/swarmy',
    download_url='https://github.com/Crunch-io/crunch-lib/archive/master.zip',

    classifiers=[
        "Programming Language :: Python",
        "Topic :: Software Development :: Libraries :: Python Modules",
    ],
    author=u'Crunch.io',
    author_email='dev@crunch.io',
    license='MIT',
    install_requires=[
        'awscli',
        'boto',
        'docopt',
    ],
    packages=find_packages(),
    #namespace_packages=['swarmy.extras'],
    include_package_data=True,
    #tests_require=testing_extras,
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

