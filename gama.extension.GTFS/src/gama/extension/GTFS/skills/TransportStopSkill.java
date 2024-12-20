package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.core.metamodel.agent.IAgent;
import gama.core.util.GamaMapFactory;
import gama.core.util.IMap;
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;
import java.util.List;

/**
 * Skill for managing individual transport stops. Provides access to stopId, stopName,
 * and detailed departure information for each stop using the updated departureInfoMap structure.
 */
@skill(name = "TransportStopSkill", doc = @doc("Skill for agents representing individual transport stops. Manages stop details, departure times, and trip information using departureInfoMap."))
@vars({
    @variable(name = "stopId", type = IType.STRING, doc = @doc("The ID of the transport stop.")),
    @variable(name = "stopName", type = IType.STRING, doc = @doc("The name of the transport stop.")),
    @variable(name = "departureInfoMap", type = IType.MAP, doc = @doc("A map where keys are departure times and values are IAgent instances for the trips.")),
    @variable(name = "orderedStopIds", type = IType.LIST, doc = @doc("The ordered list of stop IDs for the departure stop.")),
    @variable(name = "hasDepartureInfo", type = IType.BOOL, doc = @doc("Indicates whether the stop has departure information."))
})
public class TransportStopSkill extends Skill {

    // Getter for stopId
    @getter("stopId")
    public String getStopId(final IAgent agent) {
        return (String) agent.getAttribute("stopId");
    }

    // Getter for stopName
    @getter("stopName")
    public String getStopName(final IAgent agent) {
        return (String) agent.getAttribute("stopName");
    }

    // Getter for departureInfoMap
    @getter("departureInfoMap")
    @SuppressWarnings("unchecked")
    public IMap<String, IAgent> getDepartureInfoMap(final IAgent agent) {
        return (IMap<String, IAgent>) agent.getAttribute("departureInfoMap");
    }

    // Getter for orderedStopIds
    @getter("orderedStopIds")
    @SuppressWarnings("unchecked")
    public Object getOrderedStopIds(final IAgent agent) {
        return agent.getAttribute("orderedStopIds");
    }

    // New: Getter to check if departureInfoMap is not empty
    @getter("hasDepartureInfo")
    public boolean hasDepartureInfo(final IAgent agent) {
        IMap<String, IAgent> departureInfoMap = getDepartureInfoMap(agent);
        return departureInfoMap != null && !departureInfoMap.isEmpty();
    }

    // New: Retrieve stop details for a specific departure time
    @getter("stopDetailsForDepartureTime")
    public IAgent getStopDetailsForDepartureTime(final IAgent agent, final String departureTime) {
        IMap<String, IAgent> departureInfoMap = getDepartureInfoMap(agent);
        if (departureInfoMap == null || !departureInfoMap.containsKey(departureTime)) {
            System.err.println("[ERROR] No departure info found for departureTime=" + departureTime + " at stopId=" + getStopId(agent));
            return null;
        }
        return departureInfoMap.get(departureTime);
    }

    // New: Retrieve all departure times for this stop
    @getter("allDepartureTimes")
    public IMap<String, IAgent> getAllDepartureTimes(final IAgent agent) {
        return getDepartureInfoMap(agent);
    }

    // Debug: Print the departure info map
    public void debugDepartureInfoMap(final IAgent agent) {
        IMap<String, IAgent> departureInfoMap = getDepartureInfoMap(agent);
        if (departureInfoMap == null || departureInfoMap.isEmpty()) {
            System.out.println("[DEBUG] departureInfoMap is empty for stopId=" + getStopId(agent));
        } else {
            System.out.println("[DEBUG] departureInfoMap for stopId=" + getStopId(agent) + " has " 
                               + departureInfoMap.size() + " entries: " + departureInfoMap);
        }
    }

    // Debug: Print the ordered stop IDs
    public void debugOrderedStopIds(final IAgent agent) {
        Object orderedStopIds = getOrderedStopIds(agent);
        if (orderedStopIds == null || !(orderedStopIds instanceof List) || ((List<?>) orderedStopIds).isEmpty()) {
            System.out.println("[DEBUG] orderedStopIds is empty or invalid for stopId=" + getStopId(agent));
        } else {
            System.out.println("[DEBUG] orderedStopIds for stopId=" + getStopId(agent) + ": " + orderedStopIds);
        }
    }
}
