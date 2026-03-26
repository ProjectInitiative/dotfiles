from setuptools import setup, find_packages

setup(
    name="npu-analysis",
    version="1.0.0",
    description="NPU AI Network Analysis service",
    packages=find_packages(),
    scripts=["npu_analysis.py"],
    install_requires=[
        "scapy",
        "torch",
    ],
    entry_points={
        'console_scripts': [
            'npu-analysis=npu_analysis:main',
        ],
    },
)
