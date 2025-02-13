package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.annotations.precompiler.GamlAnnotations.action;
import gama.core.metamodel.agent.IAgent;
import gama.core.runtime.IScope;
import gama.core.util.GamaMapFactory;
import gama.core.util.IMap;
import gama.core.util.IList;
import gama.core.util.GamaListFactory;
import gama.core.util.GamaPair;
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;

/**
 * Skill for managing individual transport stops. Provides access to stopId, stopName,
 * and detailed departure information for each stop using the departureStopsInfo structure.
 */
@skill(name = "TransportStopSkill", doc = @doc("Skill for agents representing transport stops. Manages stop details and departure information."))
@vars({
    @variable(name = "stopId", type = IType.STRING, doc = @doc("The unique ID of the transport stop.")),
    @variable(name = "stopName", type = IType.STRING, doc = @doc("The name of the transport stop.")),
    @variable(name = "departureStopsInfo", type = IType.MAP, doc = @doc("Map where keys are trip IDs and values are lists of GamaPair<IAgent, String> (stop agent and departure time)."))
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

    // Getter for departureStopsInfo
    @getter("departureStopsInfo")
    @SuppressWarnings("unchecked")
    public IMap<String, IList<GamaPair<IAgent, String>>> getDepartureStopsInfo(final IAgent agent) {
        return (IMap<String, IList<GamaPair<IAgent, String>>>) agent.getAttribute("departureStopsInfo");
    }

 // Action to check if departureStopsInfo is not empty
    @action(name = "isDeparture")
    public boolean isDeparture(final IScope scope) {
        IAgent agent = scope.getAgent();
        @SuppressWarnings("unchecked")
		IMap<String, IList<GamaPair<IAgent, String>>> departureStopsInfo =
            (IMap<String, IList<GamaPair<IAgent, String>>>) agent.getAttribute("departureStopsInfo");

        return departureStopsInfo != null && !departureStopsInfo.isEmpty();
    }

    // Retrieve departure stop agents for a specific trip
    @getter("agentsForTrip")
    @SuppressWarnings("unchecked")
    public IList<IAgent> getAgentsForTrip(final IAgent agent, final String tripId) {
        IMap<String, IList<GamaPair<IAgent, String>>> departureStopsInfo = getDepartureStopsInfo(agent);
        if (departureStopsInfo == null || !departureStopsInfo.containsKey(tripId)) {
            System.err.println("[ERROR] No trip info found for tripId=" + tripId + " at stopId=" + getStopId(agent));
            return GamaListFactory.create();
        }
        IList<GamaPair<IAgent, String>> stopPairs = departureStopsInfo.get(tripId);
        IList<IAgent> agentsList = GamaListFactory.create();
        for (GamaPair<IAgent, String> pair : stopPairs) {
            agentsList.add(pair.getKey());
        }
        return agentsList;
    }

    // Debug: Print the departureStopsInfo
    public void debugDepartureStopsInfo(final IAgent agent) {
        IMap<String, IList<GamaPair<IAgent, String>>> departureStopsInfo = getDepartureStopsInfo(agent);
        if (departureStopsInfo == null || departureStopsInfo.isEmpty()) {
            System.out.println("[DEBUG] departureStopsInfo is empty for stopId=" + getStopId(agent));
        } else {
            System.out.println("[DEBUG] departureStopsInfo for stopId=" + getStopId(agent) + " has " 
                               + departureStopsInfo.size() + " entries: " + departureStopsInfo);
        }
    }

    // Debug: Print the stop agents for a specific trip
    public void debugAgentsForTrip(final IAgent agent, final String tripId) {
        IList<IAgent> agentsForTrip = getAgentsForTrip(agent, tripId);
        if (agentsForTrip.isEmpty()) {
            System.out.println("[DEBUG] No agents found for tripId=" + tripId + " at stopId=" + getStopId(agent));
        } else {
            System.out.println("[DEBUG] agents for tripId=" + tripId + " at stopId=" + getStopId(agent) + ": " + agentsForTrip);
        }
    }
}
