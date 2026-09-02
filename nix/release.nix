{
  version = "4.14.7";

  hashes = {
    common = {
      filebeatModule = "b0683f1d5d7c5d076ea3a565b0aa7ca92e6483f8a14e8b96799e6ee632da2284";
      filebeatTemplate = "c6e30822c67c10f7e777cb51926e261d8b2c3a941c4ffcf83325f700c1c8802f";
    };
    amd64 = {
      agent = "5276281b62e887065ecc14d4463cea529cf418529538c8edd6769c9ec550213f";
      manager = "1edd93f49ea1d89edcb7c17eeec750e99f685bc9f88d3c71f7972267c9442de0";
      indexer = "5657623a3607c9f0c3d64100b03972dd037110744bc6448382a0e0af57b95570";
      dashboard = "83f472d9e5f59b28b1abb6260c466e77b99ae427ce8c5f76203d847f2f598b6f";
      filebeat = "f759a13e5407bba184d9f0235ab88409a0d77d821e64adb3dcc0ba8e397f0201";
    };
    arm64 = {
      agent = "e5a6c90414caa9bb20ed56c3aa0f20ab7c36534632e91e968ede51e8b340da74";
      manager = "a53e85a0a89b850fdcc2b0249f723ca1f8284cee9b2a44446a1cd4a9767e8611";
      indexer = "d3d43a6a3357807eeb10e6fc6abc55910777cc5163cd4b1559df9d439b4deee5";
      dashboard = "4ef75c90167182b282ac09fed3473e394313ab1326b0072c617d69e67c4be21a";
      filebeat = "93860759c538813cfe34f88a4e4047fba45fead287a7d11fea8957c1d816cfd9";
    };
  };
}
