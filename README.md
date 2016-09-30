# backup
Automatic backup plugin for Tarantool.

Engines:
* Amazon S3

## API
You need only `start(target, opts)` function. Arguments describtion:
### target: table
* `mode`: backup mode: `tarantool` - backup instance files(wal/snap dirs)
* `schedule`: backup interval in seconds
* `bucket`: container name (like bucket in amazon s3)

### opts: table
* `engine` - backup storage engine name
* `args` - arguments for backup storage engine `init` function

### Usage
```lua
-- /etc/tarantool/instances.enabled/demo.lua
local backup = require('backup')
-- Configure auto backup in amazon s3, every 5 minutes
local backup_cfg= {
    {
        mode='tarantool',               -- we need to backup tarantool wal/snap files
        schedule=60*5,                  -- every 5 minutes
        bucket='test',                  -- into bucket "test"
        restore_to='/var/lib/tarantool',-- restore to directory
        prefix="demo"                   -- bucket/app_name prefix
    },
    {
        engine="s3" ,                   -- bucket hosted in amazon s3
        args={                          -- credentals for amazon s3
            access='your access key',
            secret='your secret key',
            region='us-east-1',
            host='host.com'
        }
    }
}

-- check env variable TNT_FROM_BACKUP and restore if needed
if os.getenv('TNT_FROM_BACKUP') ~= nil then
    backup:restore(unpack(backup_cfg))
end

-- do init and create some spaces/indexes etc...
box.cfg{}
-- ...

-- start backup fiber
backup:start(unpack(backup_cfg))
```

### Start from backup
```
$export TNT_FROM_BACKUP=1
$tarantoolctl start demo
/usr/bin/tarantoolctl: Starting instance...
/usr/bin/tarantoolctl: ---
- date: 2016-09-30T15:24:38Z
  name: tarantool/00000000000000000000.snap
  size: 1130
- date: 2016-09-30T15:24:38Z
  name: tarantool/00000000000000000000.xlog
  size: 340
...

/usr/bin/tarantoolctl: Backup "test/demo" restored to: "/var/lib/tarantool/demo"
```

