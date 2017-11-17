// frontpage.js
var settings = require("../testdata.json");

casper.test.begin('Frontpage', 2, function suite(test) {
  casper.start(settings.baseUrl , function () {
    test.assertTitle("Welcome to Drupal");
    test.assertExists("footer.footer", "Footer element is present.")
  });

  casper.run(function () {
    test.done();
  });
});
