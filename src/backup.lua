local fiber = require('fiber')
local fio = require('fio')
local log = require('log')

local function upload_by_mask(self, dir, mask, prefix)
    -- Upload files from `dir` by mask with prefix
    -- can be used in any uploaders
    local files = fio.glob(fio.pathjoin(dir, mask))
    for _, path in pairs(files) do
        local filename = fio.basename(path)
        local name = filename
        if prefix ~= nil then
            name = prefix .. '/' .. name
        end

        local ok = self.engine:upload_file(
            self.bucket, name, path
        )
        if not ok then
            return false
        end
    end
    return true
end

local function tarantool_backup(self)
    -- Tarantool backup wrapper
    -- FIXME: Currently memtx-only
    local snap_ok = upload_by_mask(
        self, box.cfg.snap_dir, '*.snap', 'tarantool'
    )
    local wal_ok = upload_by_mask(
        self, box.cfg.wal_dir, '*.xlog', 'tarantool'
    )
    return snap_ok and wal_ok
end

local function tarantool_restore(self)
end

local backup = {
    modes = {
        tarantool = {
            backup = tarantool_backup,
            restore = tarantool_restore
        },
        -- FIXME: directory backup not implemented
        directory = {
            backup = function(self)end,
            restore = function(self)end
        }
    },

    is_valid_mode = function(self, mode)
        -- check that backup mode is available
        local is_valid = false
        for m, _ in pairs(self.modes) do
            if mode == m then
                is_valid = true
                break
            end
        end
        return is_valid
    end,

    backup = function(self)
        -- common backup wrapper
        return self.modes[self.mode].backup(self)
    end,

    restore = function(self)
        -- common restore wrapper
        return self.modes[self.mode].restore(self)
    end,

    worker = function(self)
        -- backup worker
        -- FIXME: implement cron-like schedule
        fiber.name('Auto backup worker')
        while true do
            if self:backup() then
                log.info('Backup complete')
            else
                log.error('Backup failed')
            end
            fiber.sleep(self.schedule)
        end
    end,

    start = function(self, target, bucket, engine, opts)
        self.target = target
        self.bucket = bucket
        self.schedule = target.schedule
        self.mode = target.mode

        if self.mode == nil then
            return false, "Undefined mode"
        end
        if not self:is_valid_mode(self.mode) then
            return false, string.format('Unknown mode "%s"', self.mode)
        end
        if mode == 'tarantool' and type(box.cfg) ~= 'table' then
            return false, "Can't backup withou box.cfg{}"
        end
        if engine == nil then
            return false, "Undefined engine"
        end
        local args = opts.args
        if args == nil then
            return false, "Undefined engine arguments"
        end

        local _, err = pcall(function()
            self.engine = require(engine)
            self.engine:init(unpack(args))
        end)

        if err ~= nil then
            log.error(
                'Failed to start engine "%s": %s',
                engine, tostring(err)
            )
        end

        fiber.create(self.worker, self)
        log.info('Backup started on %s engine', engine)
        return true        
    end,
}

return backup
