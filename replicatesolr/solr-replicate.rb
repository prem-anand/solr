require 'json'
require 'net/http'
require 'net/ssh'
require 'pathname'

backup = ARGV[0] || "test/backup"
cluster = ARGV[1] || "http://pe-sdb3-17.int.dev.ssi-cloud.com:8080/solr"
cluster_url = URI.parse(cluster + "/admin/collections?action=clusterstatus&wt=json")
puts "Preparing restore.rb from " + backup + " using cluster url = " + cluster_url.to_s + "..."

# retrieve the cluster status
req = Net::HTTP::Get.new(cluster_url.to_s)
res = Net::HTTP.start(cluster_url.host, cluster_url.port) {|http|
  http.request(req)
}
collections = JSON.parse(res.body)

File.open("restore.sh", 'w') { |file|
  file.write("#!/usr/bin/bash\n\n")
  file.write("if [ -z \"$1\" ]; then echo \"Usage: $0 <env-prefix>\"; exit 1; else echo \"Restoring to '$1'\"; fi\n")
   
  Dir[backup + "/*"].each { |path|
    # core.persons
    collection = File.basename(path)
    file.write("# " + collection + "\n")
    Dir[path + "/*"].each { |path|
      # shard1
      shard = File.basename(path)
      replicas = collections["cluster"]["collections"][collection]["shards"][shard]["replicas"]
      replicas.each { |key, replica|
        # http://pe-sdb3-9.int.dev.ssi-cloud.com:8080/solr
        url = replica["base_url"]
        # core.persons_shard1_replica3
        core = replica["core"]
        shard_from = URI.parse(url).host
#        env, host_id, rest = shard_from.match( /(\D+)(\d+)(.*)/i ).captures
        env, host_id, rest = shard_from.match( /(.+)-(\d+)(.*)/i ).captures
        shard_to = "$1-" + host_id + rest
        
        # Retrieve the index directory
        # http://localhost:8983/solr/gettingstarted_shard1_replica1/admin/mbeans?cat=CORE&stats=true&wt=json
        core_url = URI.parse(url + "/" + core + "/admin/mbeans?cat=CORE&stats=true&wt=json")
        req = Net::HTTP::Get.new(core_url.to_s)
        res = Net::HTTP.start(core_url.host, core_url.port) {|http|
          http.request(req)
        }
        core_stats = JSON.parse(res.body)

        indexDir = core_stats["solr-mbeans"][1]["core"]["stats"]["indexDir"]
        dataDir = Pathname.new(indexDir).parent().to_s
        puts dataDir
        # ssh root@www 'ps -ef | grep apache | grep -v grep | wc -l'
        file.write("ssh " + shard_to + " 'rm -rf " + dataDir + "/* && mkdir " + indexDir + "'\n")
        file.write("scp -r " + path + "/* " + shard_to + ":" + indexDir + "\n")
      }
    }
  }
}
