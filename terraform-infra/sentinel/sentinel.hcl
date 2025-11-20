policy "ec2-instance-type" {
  source = "ec2-instance-type.sentinel"
}

policy "s3-no-public-buckets" {
  source = "s3-no-public-buckets.sentinel"
}

policy "mandatory-tags" {
  source = "mandatory-tags.sentinel"
}

mock "tfplan" {
  module {
    source = "./mocks/tfplan.json"
  }
}
