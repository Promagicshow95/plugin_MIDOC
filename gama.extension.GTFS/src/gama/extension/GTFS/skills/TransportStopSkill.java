package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.core.metamodel.agent.IAgent;
import gama.core.util.GamaMapFactory;
import gama.core.util.IMap;
import gama.extension.GTFS.TransportStop;
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;

/**
 * Skill for managing individual transport stops. Provides access to stopId, stopName,
 * and detailed departure information for each stop using the new departureInfoMap structure.
 */
@skill(name = "TransportStopSkill", doc = @doc("Skill for agents representing individual transport stops. Manages stop details, departure times, and trip information using departureInfoMap."))
@vars({
    @variable(name = "stopId", type = IType.STRING, doc = @doc("The ID of the transport stop.")),
    @variable(name = "stopName", type = IType.STRING, doc = @doc("The name of the transport stop.")),
    @variable(name = "departureInfoMap", type = IType.MAP, doc = @doc("A map where keys are departure times and values are TransportStop objects for the trips.")),
    @variable(name = "hasDepartureInfo", type = IType.BOOL, doc = @doc("Indicates whether the stop has departure information.")) // New variable
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

    // New: Getter for departureInfoMap
    @getter("departureInfoMap")
    @SuppressWarnings("unchecked")
    public IMap<String, TransportStop> getDepartureInfoMap(final IAgent agent) {
        return (IMap<String, TransportStop>) agent.getAttribute("departureInfoMap");
    }

    // New: Getter to check if departureInfoMap is not empty
    @getter("hasDepartureInfo")
    public boolean hasDepartureInfo(final IAgent agent) {
        IMap<String, TransportStop> departureInfoMap = getDepartureInfoMap(agent);
        return departureInfoMap != null && !departureInfoMap.isEmpty();
    }

    // Retrieve stop details for a specific departure time
    @getter("stopDetailsForDepartureTime")
    public TransportStop getStopDetailsForDepartureTime(final IAgent agent, final String departureTime) {
        IMap<String, TransportStop> departureInfoMap = getDepartureInfoMap(agent);
        if (departureInfoMap == null || !departureInfoMap.containsKey(departureTime)) {
            System.err.println("[Error] No departure info found for departureTime=" + departureTime + " at stop: " + getStopId(agent));
            return null;
        }
        return departureInfoMap.get(departureTime);
    }

    // Retrieve all departure times for this stop
    @getter("allDepartureTimes")
    public IMap<String, TransportStop> getAllDepartureTimes(final IAgent agent) {
        return getDepartureInfoMap(agent);
    }

    // Debug: Print the departure info map
    public void debugDepartureInfoMap(final IAgent agent) {
        IMap<String, TransportStop> departureInfoMap = getDepartureInfoMap(agent);
        if (departureInfoMap == null || departureInfoMap.isEmpty()) {
            System.out.println("[DEBUG] departureInfoMap is empty for stopId=" + getStopId(agent));
        } else {
            System.out.println("[DEBUG] departureInfoMap for stopId=" + getStopId(agent) + ": " + departureInfoMap);
        }
    }
}
