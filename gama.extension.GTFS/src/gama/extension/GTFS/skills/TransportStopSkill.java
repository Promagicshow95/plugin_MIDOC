package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.core.metamodel.agent.IAgent;
import gama.core.util.GamaMapFactory;
import gama.core.util.IMap;
import gama.core.util.IList;
import gama.core.util.GamaListFactory;
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;

/**
 * Skill for managing individual transport stops. Provides access to stopId, stopName,
 * and detailed departure information for each stop using the updated departureTripsInfo structure.
 */
@skill(name = "TransportStopSkill", doc = @doc("Skill for agents representing individual transport stops. Manages stop details, departure times, and trip information using departureTripsInfo."))
@vars({
    @variable(name = "stopId", type = IType.STRING, doc = @doc("The ID of the transport stop.")),
    @variable(name = "stopName", type = IType.STRING, doc = @doc("The name of the transport stop.")),
    @variable(name = "departureTripsInfo", type = IType.MAP, doc = @doc("A map where keys are trip IDs and values are maps containing departure time, ordered stops, and converted stops.")),
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

    // Getter for departureTripsInfo
    @getter("departureTripsInfo")
    @SuppressWarnings("unchecked")
    public IMap<String, IMap<String, Object>> getDepartureTripsInfo(final IAgent agent) {
        return (IMap<String, IMap<String, Object>>) agent.getAttribute("departureTripsInfo");
    }

    // Getter to check if departureTripsInfo is not empty
    @getter("hasDepartureInfo")
    public boolean hasDepartureInfo(final IAgent agent) {
        IMap<String, IMap<String, Object>> departureTripsInfo = getDepartureTripsInfo(agent);
        return departureTripsInfo != null && !departureTripsInfo.isEmpty();
    }

    // Retrieve converted stops for a specific trip
    @getter("convertedStopsForTrip")
    @SuppressWarnings("unchecked")
    public IList<IAgent> getConvertedStopsForTrip(final IAgent agent, final String tripId) {
        IMap<String, IMap<String, Object>> departureTripsInfo = getDepartureTripsInfo(agent);
        if (departureTripsInfo == null || !departureTripsInfo.containsKey(tripId)) {
            System.err.println("[ERROR] No trip info found for tripId=" + tripId + " at stopId=" + getStopId(agent));
            return GamaListFactory.create();
        }
        return (IList<IAgent>) departureTripsInfo.get(tripId).get("convertedStops");
    }

    // Debug: Print the departureTripsInfo
    public void debugDepartureTripsInfo(final IAgent agent) {
        IMap<String, IMap<String, Object>> departureTripsInfo = getDepartureTripsInfo(agent);
        if (departureTripsInfo == null || departureTripsInfo.isEmpty()) {
            System.out.println("[DEBUG] departureTripsInfo is empty for stopId=" + getStopId(agent));
        } else {
            System.out.println("[DEBUG] departureTripsInfo for stopId=" + getStopId(agent) + " has " 
                               + departureTripsInfo.size() + " entries: " + departureTripsInfo);
        }
    }

    // Debug: Print the ordered stops for a specific trip
    public void debugOrderedStopsForTrip(final IAgent agent, final String tripId) {
        IMap<String, IMap<String, Object>> departureTripsInfo = getDepartureTripsInfo(agent);
        if (departureTripsInfo == null || !departureTripsInfo.containsKey(tripId)) {
            System.out.println("[DEBUG] No ordered stops found for tripId=" + tripId + " at stopId=" + getStopId(agent));
        } else {
            IList<IMap<String, String>> orderedStops = (IList<IMap<String, String>>) departureTripsInfo.get(tripId).get("orderedStops");
            System.out.println("[DEBUG] orderedStops for tripId=" + tripId + " at stopId=" + getStopId(agent) + ": " + orderedStops);
        }
    }

    // Debug: Print the converted stops for a specific trip
    public void debugConvertedStopsForTrip(final IAgent agent, final String tripId) {
        IList<IAgent> convertedStops = getConvertedStopsForTrip(agent, tripId);
        if (convertedStops.isEmpty()) {
            System.out.println("[DEBUG] convertedStops is empty for tripId=" + tripId + " at stopId=" + getStopId(agent));
        } else {
            System.out.println("[DEBUG] convertedStops for tripId=" + tripId + " at stopId=" + getStopId(agent) + ": " + convertedStops);
        }
    }
}
