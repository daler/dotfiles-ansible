#!/usr/bin/python

# Modified from https://docs.ansible.com/ansible/latest/dev_guide/developing_modules_general.html

from __future__ import absolute_import, division, print_function
from pathlib import Path
import subprocess as sp

__metaclass__ = type

DOCUMENTATION = r"""
Check for existence of various programs installable via dotfiles/setup.sh, and
provide that information as facts that Ansible can operate on.
"""

EXAMPLES = r"""
"""

RETURN = r"""
"""

from ansible.module_utils.basic import AnsibleModule


def exists(program):
    p = sp.run(f"which {program}", shell=True)
    return p.returncode == 0


def pathexists(path):
    return Path(path).expanduser().exists()


def run_module():
    module_args = dict()

    result = dict(
        changed=False,
    )

    module = AnsibleModule(argument_spec=module_args, supports_check_mode=True)

    if module.check_mode:
        module.exit_json(**result)

    if not Path("~/.condarc").expanduser().exists():
        bioconda = False
    else:
        bioconda = "bioconda" in open(Path("~/.condarc").expanduser()).read()

    facts = {
        "vd": exists("vd"),
        "rg": exists("rg"),
        "conda": exists("conda"),
        "fd": exists("fd"),
        "nvim": exists("nvim"),
        "fzf": exists("fzf"),
        "npm": exists("npm"),
        "dotfiles": Path("~/.config/nvim/init.lua").expanduser().exists(),
        "bioconda": bioconda,
        "bioconda-recipes": pathexists("~/proj/bioconda-recipes"),
        "bioconda-docs": pathexists("~/proj/bioconda-docs"),
        "bioconda-utils": pathexists("~/proj/bioconda-utils"),
        "mason": pathexists("~/.local/share/nvim/mason"),
        "lazy": pathexists("~/.local/share/nvim/lazy"),
    }

    result["ansible_facts"] = facts

    module.exit_json(**result)


def main():
    run_module()


if __name__ == "__main__":
    main()
