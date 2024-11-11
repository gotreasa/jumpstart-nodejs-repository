const { hello } = require('../src/dummy.js');

describe('Check dummy', () => {
  test('should return hello world', () => {
    expect(hello()).toBe('Hello World!');
  });
});
