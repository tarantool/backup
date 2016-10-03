local fiber = require('fiber')
local yaml = require('yaml')
local fio = require('fio')
local log = require('log')

local function in_cloud(cloud, file)
    for _, elem in pairs(cloud) do
        local compare = fio.basename(elem.name)
        if file.name == compare and elem.size == file.size then
            return true
        end
    end
    return false
end

local function upload_by_mask(self, dir, mask, prefix)
    -- Upload files from `dir` by mask with prefix
    -- can be used in any uploaders
    local files = fio.glob(fio.pathjoin(dir, mask))
    local cloud_files = self.engine:list(self.target.bucket, self.target.prefix)

    for _, path in pairs(files) do
        local size = fio.stat(path).size
        local filename = fio.basename(path)
        local name = filename
        if prefix ~= nil then
            name = prefix .. '/' .. name
        end
        -- upload only new or updated files
        if not in_cloud(cloud_files, {name=filename, size=size}) then
            local ok = self.engine:upload_file(
                self.target.bucket, name, path
            )
            if not ok then
                return false
            end
        end
    end
    return true
end

local function tarantool_backup(self)
    -- Tarantool backup wrapper
    -- FIXME: Currently memtx-only
    local snap_ok = upload_by_mask(
        self, box.cfg.snap_dir, '*.snap', self.target.prefix
    )
    local wal_ok = upload_by_mask(
        self, box.cfg.wal_dir, '*.xlog', self.target.prefix
    )
    return snap_ok and wal_ok
end

local function resolve_path(self, filename)
    if string.match(fio.basename(filename), '.xlog') ~= nil then
        return self.target.restore_wal
    end
    if string.match(fio.basename(filename), '.snap') ~= nil then
        return self.target.restore_snap
    end
end

local function tarantool_restore(self)
    local files = self.engine:list(self.target.bucket, self.target.prefix)
    -- show remote storage/bucket content list to administrator
    log.info(yaml.encode(files))
    for _, file in pairs(files) do
        local path = fio.pathjoin(resolve_path(self, file.name), file.name)
        local ok = self.engine:download_file(self.target.bucket, file.name, path)
        if not ok then
            log.error('Restore operation failed')
            return false
        end
    end
    log.info(
        'Backup "%s" restored to: snaps="%s", xlogs="%s"',
        fio.pathjoin(self.target.bucket, self.target.prefix),
        fio.pathjoin(self.target.restore_snap, self.target.prefix),
        fio.pathjoin(self.target.restore_wal, self.target.prefix)
    )
    return true
end

local backup = {
    modes = {
        tarantool = {
            backup = tarantool_backup,
            restore = tarantool_restore
        },
        -- FIXME: directory backup not implemented
        -- directory = {
        --    backup = function(self)end,
        --    restore = function(self)end
        --}
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
        return self.modes[self.target.mode].backup(self)
    end,

    is_valid_restore_path = function(self, path)
        if path == nil then
            return false, "Undefined restore-path"
        end
        local restore_path = path
        if self.target.prefix ~= nil then
            restore_path = fio.pathjoin(restore_path, self.target.prefix)
        end
        if fio.stat(restore_path) == nil then
            return false, "Restore directory does not exist"
        end
        return true
    end,

    restore = function(self, target, opts)
        local ok, err = self:configure(target, opts)
        if not ok then
            return ok, err
        end
        local snap_ok, err = self:is_valid_restore_path(self.target.restore_snap)
        if not snap_ok then
            return snap_ok, err
        end
        local wal_ok, err = self:is_valid_restore_path(self.target.restore_wal)
        if not wal_ok then
            return wal_ok, err
        end
        -- common restore wrapper
        return self.modes[self.target.mode].restore(self)
    end,

    worker = function(self)
        -- backup worker
        fiber.name('Auto backup worker')
        while true do
            -- s3 tmp hach (memory leak in S3_put_object)
            self.engine = require(self.opts.engine)
            self.engine:init(self.opts.args)
            -- FIXME-1: need to find memleak in libs3
            -- FIXME-2: this code can be removed after solvig (1)

	    if self:backup() then
		log.info('Backup complete')
	    else
		log.error('Backup failed')
	    end
            fiber.sleep(self.schedule)
        end
    end,

    configure = function(self, target, opts, resotre)
        self.target = target
        self.opts = opts

        if self.target.mode == nil then
            return false, "Undefined mode"
        end
        if not self:is_valid_mode(self.target.mode) then
            return false, string.format(
                'Unknown mode "%s"', self.target.mode
            )
        end
        -- return false only in backup mode
        if self.target.mode == 'tarantool'
                and restore ~= nil and type(box.cfg) ~= 'table' then
            return false, "Can't backup without box.cfg{}"
        end
        if self.opts.engine == nil then
            return false, "Undefined engine"
        end
        if self.opts.args == nil then
            return false, "Undefined engine arguments"
        end

        local _, err = pcall(function()
            self.engine = require(self.opts.engine)
            self.engine:init(self.opts.args)
        end)

        if err ~= nil then
            log.error(
                'Failed to start engine "%s": %s',
                self.opts.engine, tostring(err)
            )
        end
        return true
    end,

    start = function(self, target, opts)
        self.schedule = target.schedule

        -- setup and check configuration
        local ok, err = self:configure(target, opts)
        if not ok then
            return ok, err
        end

        -- start backup
        fiber.create(self.worker, self)
        log.info('Backup started on %s engine', opts.engine)
        return true        
    end,
}

return backup
