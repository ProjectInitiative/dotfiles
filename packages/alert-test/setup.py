from setuptools import setup, find_packages

setup(
    name='alert-test',
    version='1.0.0',
    packages=find_packages(),
    entry_points={
        'console_scripts': [
            'alert-test=alert_test:main',
        ],
    },
)
