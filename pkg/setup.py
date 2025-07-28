import pathlib
from setuptools import setup, find_packages

ROOT_DIR = pathlib.Path(__file__).resolve().parent

REQUIREMENTS_TXT = ROOT_DIR \
    .joinpath("requirements.txt") \
    .read_text() \
    .split("\n")

setup(
    name="notebook2app",
    version="0.1.0",
    description="Deploy Python apps to Kubernetes from within a JupyterHub notebook.",
    author="",
    author_email="",
    packages=find_packages(where="src"),
    package_dir={"": "src"},
    package_data={
        "notebook2app": ["templates/*.j2"],
    },
    include_package_data=True, 
    install_requires=REQUIREMENTS_TXT,
    classifiers=[
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
    ],
)