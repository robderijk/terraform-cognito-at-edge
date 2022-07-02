const { Authenticator } = require('cognito-at-edge');

const authenticator = new Authenticator({
  // Replace these parameter values with those of your own environment
  region: request.origin.s3.customHeaders["x-user-pool-region"][0].value, // user pool region
  userPoolId: request.origin.s3.customHeaders["x-user-pool-id"][0].value, // user pool ID
  userPoolAppId: request.origin.s3.customHeaders["x-user-pool-app-client-id"][0].value, // user pool app client ID
  userPoolDomain: request.origin.s3.customHeaders["x-user-pool-domain"][0].value, // user pool domain
});

exports.handler = async (request) => authenticator.handle(request);