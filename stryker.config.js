// @ts-check
/** @type {import('@stryker-mutator/api/core').PartialStrykerOptions} */
const config = {
  _comment:
    "This config was generated using 'stryker init'. Please take a look at: https://stryker-mutator.io/docs/stryker-js/configuration/ for more information.",
  packageManager: 'npm',
  reporters: ['html', 'clear-text', 'progress'],
  testRunner: 'jest',
  testRunner_comment:
    'Take a look at https://stryker-mutator.io/docs/stryker-js/jest-runner for information about the jest plugin.',
  coverageAnalysis: 'off',
  // Keep generated reports out of the sandbox; kcov's output holds
  // symlinks that Stryker cannot copy
  ignorePatterns: ['/coverage'],
  jest: {
    projectType: 'custom',
    configFile: 'jest.config.js',
    config: {
      testEnvironment: 'node',
    },
    enableFindRelatedTests: true,
  },
};
export default config;
