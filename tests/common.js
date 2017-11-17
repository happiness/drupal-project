/**
 * Generates a random string of ASCII characters of codes 32 to 126
 *
 * @param Number length
 *   Length of random string to generate.
 * @returns String
 *   Randomly generated string.
 */
randomString = function(length) {
  length = length || 8;

  var str = String.fromCharCode(97 + Math.floor((Math.random() * 26)));
  var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  for (i = 1; i < length; i++) {
    str += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return str;
}

/**
 * Generates a random username.
 *
 * @return String
 *   A random username.
 */
randomUsername = function() {
  var rnd = randomString(6);
  return 'test_' + rnd;
}

/**
 * Generates a random mail address.
 *
 * @return String
 *   A random email address.
 */
randomMail =  function() {
  var rnd = randomString(6);
  return 'test_' + rnd + '@priushealth.org';
}
