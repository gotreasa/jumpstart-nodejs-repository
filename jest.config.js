import { defaults } from 'jest-config';

export default {
  clearMocks: true,
  collectCoverage: true,
  verbose: true,
  coverageThreshold: {
    global: {
      branches: 100,
      functions: 100,
      lines: 100,
      statements: 0,
    },
  },
  moduleFileExtensions: [...defaults.moduleFileExtensions, 'feature'],
  moduleNameMapper: { '^uuid$': 'uuid' },
  reporters: [
    'default',
    [
      'jest-junit',
      {
        outputDirectory: 'reports',
        outputName: 'jest-junit.xml',
        uniqueOutputName: 'true',
      },
    ],
  ],
  resetMocks: true,
  resetModules: true,
  testEnvironment: 'node',
  testMatch: [...defaults.testMatch, '**/*_steps.js', '**/*.spec.mjs'],
  transform: {
    '^.+\\.(js|jsx)$': 'babel-jest',
  },
  watchPathIgnorePatterns: [
    ...defaults.watchPathIgnorePatterns,
    '.stryker-tmp/*',
  ],
};
