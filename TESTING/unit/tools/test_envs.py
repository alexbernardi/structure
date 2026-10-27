import unittest
from pathlib import Path
from unittest import mock

import toolhelpers
from structure_cli import envs, paths


def env(name="alpha", **overrides):
    values = {"STRUCTURE_ENV_ID": name, "STRUCTURE_PORT": "24700", "STRUCTURE_WORLD_ID": "alpha", "STRUCTURE_WORLD_SEED": "5"}
    values.update(overrides)
    return envs.Environment(name, values, Path("unused"))


class EnvironmentTest(unittest.TestCase):
    def test_valid_environment(self):
        self.assertEqual(envs.validate(env()), [])

    def test_invalid_values_are_reported(self):
        problems = envs.validate(env(STRUCTURE_PORT="80", STRUCTURE_WORLD_ID="Bad World", STRUCTURE_WORLD_SEED="-1"))
        self.assertEqual(len(problems), 3, problems)

    def test_id_must_match_file_name(self):
        self.assertTrue(envs.validate(env(STRUCTURE_ENV_ID="other")))

    def test_public_bind_needs_explicit_opt_in(self):
        self.assertTrue(envs.validate(env(STRUCTURE_BIND="0.0.0.0")))
        self.assertEqual(envs.validate(env(STRUCTURE_BIND="0.0.0.0", STRUCTURE_ALLOW_PUBLIC_BIND="yes")), [])

    def test_port_collisions_are_detected(self):
        problems = envs.validate_set([env("alpha"), env("beta", STRUCTURE_WORLD_ID="beta")])
        self.assertTrue(any("already used" in p for p in problems), problems)

    def test_committed_environments_are_valid_and_isolated(self):
        all_envs = envs.all_envs()
        self.assertEqual(envs.validate_set(all_envs), [])
        self.assertEqual(len({e.data_dir for e in all_envs}), len(all_envs), "every environment has its own data dir")
        self.assertEqual(len({e.compose_project for e in all_envs}), len(all_envs))

    def test_env_file_parsing_and_local_override(self):
        tmp = toolhelpers.temp_dir("envfile")
        try:
            path = tmp / "x.env"
            path.write_text("# comment\nSTRUCTURE_PORT=24700\nSTRUCTURE_WORLD_ID='quoted'\n\n", encoding="utf-8")
            self.assertEqual(envs.parse_env_file(path), {"STRUCTURE_PORT": "24700", "STRUCTURE_WORLD_ID": "quoted"})
            path.write_text("NOT A PAIR\n", encoding="utf-8")
            with self.assertRaises(envs.EnvError):
                envs.parse_env_file(path)
            folder = tmp / "envs"
            folder.mkdir()
            (folder / "zeta.env").write_text("STRUCTURE_ENV_ID=zeta\nSTRUCTURE_PORT=24701\nSTRUCTURE_WORLD_ID=zeta\n"
                                             "STRUCTURE_WORLD_SEED=1\n", encoding="utf-8")
            (folder / "zeta.local.env").write_text("STRUCTURE_PORT=24799\n", encoding="utf-8")
            with mock.patch.object(paths, "ENVIRONMENTS", folder):
                loaded = envs.load("zeta")
                self.assertEqual(loaded.port, 24799, "git-ignored local file overrides the committed one")
                self.assertNotIn("zeta.local", [e.name for e in envs.all_envs()])
        finally:
            toolhelpers.cleanup(tmp)


if __name__ == "__main__":
    unittest.main()
