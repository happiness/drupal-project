# Testing with CasperJS

To get started:

* Install dependencies by runing `./tests/npm install`
* Setup your test data (`./tests/testdata.json`) by settings appropriate values

To run all tests in the folder `./tests/tests` run `./tests/runtests.sh`.

To run a single test, from within the `./tests` directory, run
`./casperjs test tests/login.js` for example.

## Setup and tear down

In the directory `./tests/scripts` there are two scripts responsible for
setting up and tearing down test data that are needed during test runs.

The setup script creates a user with the username and password specified in
`./tests/testdata.json`.

The tear down script is responsible for removing any data created in the
setup.