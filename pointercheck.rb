#!/usr/bin/env ruby
require 'json'
require 'yaml'

unless ARGV.size > 0
  ARGV.concat Dir['./**/*.sdf.json']
end

jps = %w[
 sdfRef
 sdfRequired
 sdfInputData
 sdfRequiredInputData
 sdfOutputData
]

# Generate all the positions in a tree as an
# array of JSON pointers, each prefixed by "input"
def gen_pointers(spec, input)
  case spec
  when Hash
    [input] + spec.map { |k, v|
      gen_pointers(v, input + "/" + k)
    }.flatten
  else
    [input]
  end
end

# Search for a map key and return value, $..["label"]
# mutating "input"!
def descend(input, position, label)
  # p [input, position, label]
  case position
  when Hash
    if position.has_key?(label)

      case s = position[label]
      when String
        input << s
      when Array
        input.concat s
      end
    end
    position.each { |k, v|
      descend(input, v, label)
    }
  when Array
    position.each { |v|
      descend(input, v, label)
    }
  end
  input
end

globalref = []
globaldef = Hash.new {|h,k|h[k] = []}

def de_curie(curie, ns, dns)
  if curie =~ /^([a-zA-Z_][-.0-9a-zA-Z_]*):(.*)/
    prefix = $1
    unless base = ns[prefix]
      warn "*** unknown prefix #{prefix}"
    end
    "#{base}#$2"
  else
    "#{dns}#{curie}"
  end
end

ARGV.each do |fn|
  spec = JSON.load(File.read(fn))
  copr = spec["info"]["copyright"].sub(/Copyright ?(\(c\))? ?(20..(-20..)?)?,? ?/, "")
           .sub(/ ?All rights reserved./, "")
  ns = spec["namespace"]
  if spec["defaultnamespace"]
    warn "*** #{fn} defaultNamespace misspelled as defaultnamespace"
  end
  dns_name = spec["defaultNamespace"]
  if dns_name
    dns = ns[dns_name]
    warn "*** #{fn}: defaultNamespace #{dns_name} doesn't point to defined namespace" unless dns
  else
    dns = "file:///#{File.basename(fn)}/"
  end
  bad = []
  pointers = jps.map {|jp| descend([], spec, jp)}.flatten.uniq
  # puts({file: fn, owner: copr, dns: dns, ref: pointers}.to_yaml)
  globalref.concat(pointers.map {|p| {ref: de_curie(p, ns, dns), file: fn, copr: copr, ns: ns, dns: dns}})

  # now create populated namespace; store it in another structure
  # Go through "global" refs...

  # Generate the pointers with URI/fragment-ID format
  gen_pointers(spec, dns + "#").each do |uri|
    globaldef[uri] << {fn: fn}
  end

  next
end

# Do some duplicate handling on globaldef

# puts globalref.to_yaml
# puts globaldef.to_yaml
# 3.times {puts}

missing = []

globalref.each do |ref|
  fn = ref[:file]
  ref = ref[:ref]
  case ref
  when String
    # ref.gsub!("##", "#")           # XXX
    a = globaldef[ref]
    if a == []
      refs = ref.split("/")
      n = refs.count-1
      while n > 0 && globaldef[refs[0...n].join("/")] == []
        n -= 1
      end
      refs[n] = ">>#{refs[n]}<<"
      missing << {ref: refs.join("/"), fn: fn}
    elsif a.size != 1
      puts({ref: ref, fn: fn, defs: a}.to_yaml)
    end
  else
    p ["***", ref]
  end
end

puts({missing: missing}.to_yaml) if missing != []
