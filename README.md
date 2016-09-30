# backup
Automatic backup plugin for Tarantool. In progress

Engines:
* Amazon S3

## API
You need only `start(target, opts)` function. Arguments describtion:
### target: table
* `mode`: backup mode: `directory` - backup directory, `tarantool` - backup instance files(wal/snap dirs)
* `schedule`: backup interval in seconds
* `bucket`: container name (like bucket in amazon s3)
* `dir`: path to directory (optional, used in directory mode)
### opts: table
* `engine` - backup storage engine name
* `args` - arguments for backup storage engine `init` function

Usage:
```lua
box.cfg{}

-- create some spaces/indexes etc.

-- Configure and start auto backup in amazon s3, every 5 minutes
require('backup'):start(
    {mode='tarantool', schedule=60*5, bucket='test'},
    {engine="s3" ,args={
	access='your access key',
	secret='your secret key',
	region='us-east-1',
        host='host.com'
    }}
)
```
