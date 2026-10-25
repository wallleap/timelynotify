import localUnitTest from './LocalUnit.test';
import testPushExampleTest from './TestPushExample.test';
import markdownTest from './Markdown.test';

export default function testsuite() {
  localUnitTest();
  testPushExampleTest();
  markdownTest();
}
