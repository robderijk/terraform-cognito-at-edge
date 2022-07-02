const { Authenticator } = require('cognito-at-edge');

const authenticator = new Authenticator({
  // Replace these parameter values with those of your own environment
  region: process.env.USER_POOL_REGION, // user pool region
  userPoolId: process.env.USER_POOL_ID, // user pool ID
  userPoolAppId: process.env.USER_POOL_APP_CLIENT_ID, // user pool app client ID
  userPoolDomain: process.env.USER_POOL_DOMAIN, // user pool domain
});

exports.handler = async (request) => authenticator.handle(request);