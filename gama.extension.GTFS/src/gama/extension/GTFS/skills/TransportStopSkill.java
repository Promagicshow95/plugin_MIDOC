package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.setter;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.core.metamodel.agent.IAgent;
import gama.core.util.IList;
import gama.core.util.IMap;
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;

/**
 * The skill TransportStopSkill for managing individual transport stops in GAMA.
 * This skill stores attributes like stopId, stopName, tripAssociations, and destinationMap for each stop.
 */
@skill(name = "TransportStopSkill", doc = @doc("Skill for agents that represent individual transport stops with attributes like stopId, stopName, tripAssociations, and destinationMap."))
@vars({
    @variable(name = "stopId", type = IType.STRING, doc = @doc("The ID of the transport stop.")),
    @variable(name = "stopName", type = IType.STRING, doc = @doc("The name of the transport stop.")),
    @variable(name = "tripAssociations", type = IType.MAP, doc = @doc("A map of trip IDs to the list of predecessor stops (IList<TransportStop>).")),
    @variable(name = "destinationMap", type = IType.MAP, doc = @doc("A map of trip IDs to their destination stop IDs."))
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

    // Getter and setter for tripAssociations
    @SuppressWarnings("unchecked")
    @getter("tripAssociations")
    public IMap<Integer, IList<IAgent>> getTripAssociations(final IAgent agent) {
        return (IMap<Integer, IList<IAgent>>) agent.getAttribute("tripAssociations");
    }

    @setter("tripAssociations")
    public void setTripAssociations(final IAgent agent, final IMap<Integer, IList<IAgent>> tripAssociations) {
        agent.setAttribute("tripAssociations", tripAssociations);
    }

    // Getter and setter for destinationMap
    @SuppressWarnings("unchecked")
    @getter("destinationMap")
    public IMap<Integer, String> getDestinationMap(final IAgent agent) {
        return (IMap<Integer, String>) agent.getAttribute("destinationMap");
    }

    @setter("destinationMap")
    public void setDestinationMap(final IAgent agent, final IMap<Integer, String> destinationMap) {
        agent.setAttribute("destinationMap", destinationMap);
    }

    // Optional: Utility method to retrieve the destination for a specific trip
    @getter("destination")
    public String getDestinationForTrip(final IAgent agent, final int tripId) {
        IMap<Integer, String> destinations = getDestinationMap(agent);
        return destinations != null ? destinations.get(tripId) : null;
    }
}
