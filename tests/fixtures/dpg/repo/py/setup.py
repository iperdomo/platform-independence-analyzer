from setuptools import setup
setup(name="x", install_requires=["stripe>=5", "requests"],
      extras_require={"mail": ["sendgrid"], "dev": ["black"]})
REQS = ["mixpanel"]
setup(name="y", install_requires=REQS, tests_require=open("x").read().split())
