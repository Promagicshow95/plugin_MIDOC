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
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;
import gama.gaml.types.Types;

/**
 * Skill for managing individual transport stops. Provides access to stopId, stopName,
 * and detailed departure information for each stop.
 */
@skill(name = "TransportStopSkill", doc = @doc("Skill for agents representing individual transport stops. Manages stop details, departure times, and trip information."))
@vars({
    @variable(name = "stopId", type = IType.STRING, doc = @doc("The ID of the transport stop.")),
    @variable(name = "stopName", type = IType.STRING, doc = @doc("The name of the transport stop.")),
    @variable(name = "departureInfoList", type = IType.LIST, doc = @doc("A list containing trips with departure times and their associated stops.")),
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

    // Getter for departureInfoList
    @getter("departureInfoList")
    public IList<IList<Object>> getDepartureInfoList(final IAgent agent) {
        return (IList<IList<Object>>) agent.getAttribute("departureInfoList");
    }

    // New: Getter to check if departureInfoList is not empty
    @getter("hasDepartureInfo")
    public boolean hasDepartureInfo(final IAgent agent) {
        IList<IList<Object>> departureInfoList = getDepartureInfoList(agent);
        return departureInfoList != null && !departureInfoList.isEmpty();
    }

    // Retrieve stop details for a specific trip
    @getter("stopDetailsForTrip")
    public IList<IMap<String, String>> getStopDetailsForTrip(final IAgent agent, final int tripIndex) {
        IList<IList<Object>> departureInfoList = getDepartureInfoList(agent);
        if (departureInfoList == null || tripIndex >= departureInfoList.size()) {
            System.err.println("[Error] Invalid trip index or departureInfoList is empty for stop: " + getStopId(agent));
            return GamaListFactory.create();
        }

        IList<Object> tripData = departureInfoList.get(tripIndex);
        @SuppressWarnings("unchecked")
        IList<IMap<String, Object>> stopsForTrip = (IList<IMap<String, Object>>) tripData.get(1);

        IList<IMap<String, String>> stopDetails = GamaListFactory.create();
        for (IMap<String, Object> stopEntry : stopsForTrip) {
            IMap<String, String> details = GamaMapFactory.create();
            details.put("stopId", (String) stopEntry.get("stopId"));
            details.put("departureTime", (String) stopEntry.get("departureTime"));
            stopDetails.add(details);
        }
        return stopDetails;
    }

    // Retrieve global departure time for a trip
    @getter("globalDepartureTimeForTrip")
    public String getGlobalDepartureTimeForTrip(final IAgent agent, final int tripIndex) {
        IList<IList<Object>> departureInfoList = getDepartureInfoList(agent);
        if (departureInfoList == null || tripIndex >= departureInfoList.size()) {
            System.err.println("[Error] Invalid trip index for stop: " + getStopId(agent));
            return null;
        }
        return (String) departureInfoList.get(tripIndex).get(0);
    }
}
