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
    p = sp.run(f"which {program}", shell=True, check=False)
    return p.returncode == 0


def pathexists(path):
    return Path(path).expanduser().exists()


def installed_but_needs_link(env_executable, link):
    """
    For example, if it was installed on persistent storage, but it's a fresh
    instance where ~/opt/bin is not populated
    """
    if pathexists(env_executable) and not pathexists(link):
        return True
    return False


def installed_but_not_on_path(env_dir, program):
    """
    Same as above, but looking for presence on PATH rather than a symlink in
    ~/opt/bin
    """
    if pathexists(env_dir) and not exists(program):
        return True
    return False


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
        "conda": exists("conda") or pathexists("/data/miniforge/bin"),
        "fd": exists("fd") and not installed_but_needs_link("/data/miniforge/envs/fd/bin/fd", "~/opt/bin/fd"),
        "fd_needs_link": installed_but_needs_link("/data/miniforge/envs/fd/bin/fd", "~/opt/bin/fd"),
        "vd_needs_link": installed_but_needs_link("/data/miniforge/envs/visidata/bin/vd", "~/opt/bin/vd"),
        "npm_needs_path": installed_but_not_on_path("/data/miniforge/envs/npm/bin", "npm"),
        "conda_needs_path": installed_but_not_on_path("/data/miniforge/condabin", "conda"),
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
