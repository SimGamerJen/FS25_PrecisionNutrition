PNMetricsEvent = {}
local PNMetricsEvent_mt = Class(PNMetricsEvent, Event)
InitEventClass(PNMetricsEvent, "PNMetricsEvent")
local MAX_NETWORK_ANIMALS = 60

function PNMetricsEvent.emptyNew()
    return Event.new(PNMetricsEvent_mt)
end

function PNMetricsEvent.new(metric, reset)
    local self = PNMetricsEvent.emptyNew()
    self.metric = metric
    self.reset = reset == true
    return self
end

function PNMetricsEvent:writeStream(streamId, connection)
    local metric = self.metric
    streamWriteBool(streamId, self.reset)
    streamWriteString(streamId, metric.key or "")
    streamWriteString(streamId, metric.name or "")
    streamWriteInt32(streamId, metric.farmId or 0)
    streamWriteString(streamId, metric.species or "DEFAULT")
    streamWriteInt32(streamId, metric.head or 0)
    streamWriteFloat32(streamId, metric.baseFood or 0)
    streamWriteFloat32(streamId, metric.effectiveFood or 0)
    streamWriteFloat32(streamId, metric.energy or 0)
    streamWriteFloat32(streamId, metric.protein or 0)
    streamWriteFloat32(streamId, metric.quality or 0)
    streamWriteFloat32(streamId, metric.dryMatterKg or 0)
    streamWriteFloat32(streamId, metric.unknownKg or 0)
    streamWriteString(streamId, metric.stages or "")
    streamWriteString(streamId, metric.stamp or "")
    local individuals = metric.individuals or {}
    local count = math.min(#individuals, MAX_NETWORK_ANIMALS)
    streamWriteInt32(streamId, metric.individualTotal or #individuals)
    streamWriteInt32(streamId, count)
    for index = 1, count do
        local animal = individuals[index]
        streamWriteString(streamId, animal.id or "")
        streamWriteString(streamId, animal.name or "")
        streamWriteInt32(streamId, animal.head or 1)
        streamWriteString(streamId, animal.species or metric.species or "DEFAULT")
        streamWriteString(streamId, animal.stage or "DEFAULT")
        streamWriteString(streamId, animal.gender or "")
        streamWriteFloat32(streamId, animal.age or 0)
        streamWriteFloat32(streamId, animal.weight or 0)
        streamWriteFloat32(streamId, animal.targetWeight or 0)
        streamWriteFloat32(streamId, animal.health or 0)
        streamWriteBool(streamId, animal.pregnant == true)
        streamWriteBool(streamId, animal.lactating == true)
        streamWriteBool(streamId, animal.castrated == true)
        streamWriteFloat32(streamId, animal.energy or 0)
        streamWriteFloat32(streamId, animal.protein or 0)
        streamWriteFloat32(streamId, animal.quality or 0)
        streamWriteFloat32(streamId, animal.baseFood or 0)
        streamWriteFloat32(streamId, animal.effectiveFood or 0)
    end
end

function PNMetricsEvent:readStream(streamId, connection)
    self.reset = streamReadBool(streamId)
    local metric = {
        key=streamReadString(streamId), name=streamReadString(streamId), farmId=streamReadInt32(streamId),
        species=streamReadString(streamId), head=streamReadInt32(streamId), baseFood=streamReadFloat32(streamId),
        effectiveFood=streamReadFloat32(streamId), energy=streamReadFloat32(streamId),
        protein=streamReadFloat32(streamId), quality=streamReadFloat32(streamId),
        dryMatterKg=streamReadFloat32(streamId), unknownKg=streamReadFloat32(streamId),
        stages=streamReadString(streamId), stamp=streamReadString(streamId)
    }
    metric.individualTotal = streamReadInt32(streamId)
    metric.individuals = {}
    local count = streamReadInt32(streamId)
    for _ = 1, count do
        table.insert(metric.individuals, {
            id=streamReadString(streamId), name=streamReadString(streamId), head=streamReadInt32(streamId),
            species=streamReadString(streamId), stage=streamReadString(streamId), gender=streamReadString(streamId),
            age=streamReadFloat32(streamId), weight=streamReadFloat32(streamId),
            targetWeight=streamReadFloat32(streamId), health=streamReadFloat32(streamId),
            pregnant=streamReadBool(streamId), lactating=streamReadBool(streamId),
            castrated=streamReadBool(streamId), energy=streamReadFloat32(streamId),
            protein=streamReadFloat32(streamId), quality=streamReadFloat32(streamId),
            baseFood=streamReadFloat32(streamId), effectiveFood=streamReadFloat32(streamId)
        })
    end
    self.metric = metric
    self:run(connection)
end

function PNMetricsEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        if self.reset then PN_Core.metricsByKey = {} end
        if self.metric.key ~= "" then PN_Core.applyRemoteMetric(self.metric) end
    end
end

PN_Events = PN_Events or {}

function PN_Events.broadcastSnapshot()
    if g_server == nil or not g_server.netIsRunning then return end
    local metrics = PN_Core.getMetrics(nil)
    if #metrics == 0 then
        g_server:broadcastEvent(PNMetricsEvent.new({ key="" }, true))
        return
    end
    for index, metric in ipairs(metrics) do
        g_server:broadcastEvent(PNMetricsEvent.new(metric, index == 1))
    end
end

return PN_Events
