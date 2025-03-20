package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.annotations.precompiler.GamlAnnotations.action;
import gama.core.metamodel.agent.IAgent;
import gama.core.runtime.IScope;
import gama.core.util.IMap;
import gama.core.util.IList;
import gama.core.util.GamaListFactory;
import gama.core.util.GamaPair;
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;

/**
 * Skill for managing individual transport stops. Provides access to stopId, stopName,
 * routeType, and detailed departure information for each stop using the departureStopsInfo structure.
 */
@skill(name = "TransportStopSkill", doc = @doc("Skill for agents representing transport stops. Manages stop details, routeType, and departure information."))
@vars({
    @variable(name = "stopId", type = IType.STRING, doc = @doc("The unique ID of the transport stop.")),
    @variable(name = "stopName", type = IType.STRING, doc = @doc("The name of the transport stop.")),
    @variable(name = "routeType", type = IType.INT, doc = @doc("The type of transport route associated with the stop.")),
    @variable(name = "departureStopsInfo", type = IType.MAP, doc = @doc("Map where keys are trip IDs and values are lists of GamaPair<IAgent, String> (stop agent and departure time).")),
    @variable(name = "tripShapeMap", type = IType.MAP, doc = @doc("Mape where keys are trip IDS and values are shape IDS"))
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

    // Getter for routeType
    @getter("routeType")
    public int getRouteType(final IAgent agent) {
        return (int) agent.getAttribute("routeType");
    }

    // Getter for departureStopsInfo
    @SuppressWarnings("unchecked")
    @getter("departureStopsInfo")
    public IMap<String, IList<GamaPair<IAgent, String>>> getDepartureStopsInfo(final IAgent agent) {
        return (IMap<String, IList<GamaPair<IAgent, String>>>) agent.getAttribute("departureStopsInfo");
    }
    
 // Getter for tripShapeMap
    @SuppressWarnings("unchecked")
    @getter("tripShapeMap")
    public IMap<String, Integer> tripShapeMap(final IAgent agent) {
        return (IMap<String, Integer>) agent.getAttribute("tripShapeMap");
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
}
