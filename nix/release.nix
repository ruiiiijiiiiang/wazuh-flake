{
  version = "4.14.9";

  hashes = {
    common = {
      filebeatModule = "7a8c67c47b22f89ab271b7e35f108f18b2215b7aa411cdd23c9994393070d38d";
      filebeatTemplate = "b2d182f49cc68957849e77fd2d79528fd2273ebaec1106c9661c9e320577a089";
    };
    amd64 = {
      agent = "20178fe13fa8fa4742dd3db3a19efaeed15faa79749fc47f606ca61a7ccad1f4";
      manager = "8b6f615f84c93a51c6023e7e542b9519945684434b117396ae61517bcdcba5f8";
      indexer = "58f39b644115d18718a442ad796d0819cb9825110999106558392454f9035e21";
      dashboard = "8e23cf07233083f4cd57c85518425bb45e9a3aa3c690b5593709cc0324019746";
      filebeat = "f759a13e5407bba184d9f0235ab88409a0d77d821e64adb3dcc0ba8e397f0201";
    };
    arm64 = {
      agent = "7a8c36c9b6d2c2c22ed27e9dd467a27cc3cb32660109f98c2db1a3c39c9f7278";
      manager = "de20efb4e24161c0f11af5ce53d521ae16c2f7e770e73b902f1e7ac70e9b3ef8";
      indexer = "57b5a30a4dbb7588b42fd1ef9af8b92ecb8b737e024a51511ecac17e0dfb3675";
      dashboard = "0396d397d17b265655f891130164f37dfb0bc64b998615ceb0025c44c00ab593";
      filebeat = "93860759c538813cfe34f88a4e4047fba45fead287a7d11fea8957c1d816cfd9";
    };
  };
}
