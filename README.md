# backup
Automatic backup plugin for Tarantool. In progress

Engines:
* Amazon S3

### API
You need only `start(target, bucket, engine, opts)` function:
* `target` - lua table with fields: mode(`directory`, `tarantool`), dir(used in directory mode), schedule (backup intervals)
* `bucket` - name of container in storage engine (like bucket in s3)
* `engine` - storage engine name
* `opts` - backup options: `args` - arguments for engine `init` function

Usage:
```lua
box.cfg{}

-- create some spaces/indexes etc.

-- Configure and start auto backup in amazon s3
require('backup'):start(
    {mode='tarantool', schedule=60}, 'test', 's3',
    {
        args={
	    'token', 'secret_key',
	    'us-east-1', 'host.com'
        }
    }
)
```
