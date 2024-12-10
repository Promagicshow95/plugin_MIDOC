package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.setter;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.core.metamodel.agent.IAgent;
import gama.core.util.GamaListFactory;
import gama.core.util.GamaMapFactory;
import gama.core.util.IList;
import gama.core.util.IMap;
import gama.extension.GTFS.TransportStop;
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;

/**
 * The skill TransportStopSkill for managing individual transport stops in GAMA.
 * This skill provides access to stopId, stopName, and structured departureInfoList for each stop.
 */
@skill(name = "TransportStopSkill", doc = @doc("Skill for agents representing individual transport stops. Provides access to stopId, stopName, and detailed departure information."))
@vars({
    @variable(name = "stopId", type = IType.STRING, doc = @doc("The ID of the transport stop.")),
    @variable(name = "stopName", type = IType.STRING, doc = @doc("The name of the transport stop.")),
    @variable(name = "departureInfoList", type = IType.LIST, doc = @doc("A list containing trips with departure times and their associated stops."))
})
public class TransportStopSkill extends Skill {

    // Getter and setter for stopId
    @getter("stopId")
    public String getStopId(final IAgent agent) {
        return (String) agent.getAttribute("stopId");
    }

    @setter("stopId")
    public void setStopId(final IAgent agent, final String stopId) {
        agent.setAttribute("stopId", stopId);
    }

    // Getter and setter for stopName
    @getter("stopName")
    public String getStopName(final IAgent agent) {
        return (String) agent.getAttribute("stopName");
    }

    @setter("stopName")
    public void setStopName(final IAgent agent, final String stopName) {
        agent.setAttribute("stopName", stopName);
    }

    // Getter for departureInfoList
    @getter("departureInfoList")
    @SuppressWarnings("unchecked")
    public IList<IList<Object>> getDepartureInfoList(final IAgent agent) {
        return (IList<IList<Object>>) agent.getAttribute("departureInfoList");
    }

    // Utility method: Retrieve all stop IDs and names for a given trip
    @getter("stopDetailsForTrip")
    @SuppressWarnings("unchecked")
    public IList<IMap<String, String>> getStopDetailsForTrip(final IAgent agent, final int tripIndex) {
        IList<IList<Object>> departureInfoList = getDepartureInfoList(agent);
        if (departureInfoList == null || tripIndex >= departureInfoList.size()) {
            return null;
        }

        // Extract the stops for the specified trip
        IList<Object> tripData = departureInfoList.get(tripIndex);
        IList<IMap<String, Object>> stopsForTrip = (IList<IMap<String, Object>>) tripData.get(1);

        // Extract the IDs and names of stops
        IList<IMap<String, String>> stopDetails = gama.core.util.GamaListFactory.create();
        for (IMap<String, Object> stopEntry : stopsForTrip) {
            IMap<String, String> details = GamaMapFactory.create();
            TransportStop stop = (TransportStop) stopEntry.get("stop");
            details.put("stopId", stop.getStopId());
            details.put("stopName", stop.getStopName());
            stopDetails.add(details);
        }
        return stopDetails;
    }

    // Utility method: Retrieve the departure times of stops for a given trip
    @getter("departureTimesForTrip")
    @SuppressWarnings("unchecked")
    public IList<String> getDepartureTimesForTrip(final IAgent agent, final int tripIndex) {
        IList<IList<Object>> departureInfoList = getDepartureInfoList(agent);
        if (departureInfoList == null || tripIndex >= departureInfoList.size()) {
            return null;
        }

        // Extract the stops for the specified trip
        IList<Object> tripData = departureInfoList.get(tripIndex);
        IList<IMap<String, Object>> stopsForTrip = (IList<IMap<String, Object>>) tripData.get(1);

        // Extract the departure times
        IList<String> departureTimes = GamaListFactory.create();
        for (IMap<String, Object> stopEntry : stopsForTrip) {
            String departureTime = (String) stopEntry.get("departureTime");
            departureTimes.add(departureTime);
        }
        return departureTimes;
    }

    // Utility method: Retrieve the global departure time for a specific trip
    @getter("globalDepartureTimeForTrip")
    public String getGlobalDepartureTimeForTrip(final IAgent agent, final int tripIndex) {
        IList<IList<Object>> departureInfoList = getDepartureInfoList(agent);
        if (departureInfoList == null || tripIndex >= departureInfoList.size()) {
            return null;
        }

        // Extract the global departure time
        IList<Object> tripData = departureInfoList.get(tripIndex);
        return (String) tripData.get(0);
    }

    // Utility method: Retrieve the complete details of a trip
    @getter("tripDetails")
    @SuppressWarnings("unchecked")
    public IMap<String, Object> getTripDetails(final IAgent agent, final int tripIndex) {
        IList<IList<Object>> departureInfoList = getDepartureInfoList(agent);
        if (departureInfoList == null || tripIndex >= departureInfoList.size()) {
            return null;
        }

        // Extract trip details
        IList<Object> tripData = departureInfoList.get(tripIndex);
        String globalDepartureTime = (String) tripData.get(0);
        IList<IMap<String, Object>> stopsForTrip = (IList<IMap<String, Object>>) tripData.get(1);

        IMap<String, Object> tripDetails = GamaMapFactory.create();
        tripDetails.put("globalDepartureTime", globalDepartureTime);
        tripDetails.put("stops", stopsForTrip);

        return tripDetails;
    }
}

           
