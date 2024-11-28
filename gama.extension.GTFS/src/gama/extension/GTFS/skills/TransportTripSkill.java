package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.setter;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.gaml.skills.Skill;
import gama.core.metamodel.agent.IAgent;
import gama.gaml.types.IType;

/**
 * The skill TransportTripSkill for managing individual transport trips in GAMA.
 * This skill stores attributes like tripId, routeId, serviceId, directionId, and shapeId for each trip.
 */
@skill(name = "TransportTripSkill", doc = @doc("Skill for agents that represent individual transport trips with attributes like tripId, routeId, serviceId, directionId, and shapeId."))
@vars({
    @variable(name = "tripId", type = IType.INT, doc = @doc("The ID of the transport trip.")),
    @variable(name = "routeId", type = IType.STRING, doc = @doc("The ID of the route associated with the trip.")),
    @variable(name = "stopsInOrder", type = IType.LIST, doc = @doc("The ordered list of stops in the trip.")),
    @variable(name = "destination", type = IType.AGENT, doc = @doc("The final stop in the trip.")),
    @variable(name = "predecessors", type = IType.LIST, doc = @doc("The list of stops before a specific stop in the trip."))
})
public class TransportTripSkill extends Skill {

    // Getter and setter for tripId
    @getter("tripId")
    public int getTripId(final IAgent agent) {
        return (Integer) agent.getAttribute("tripId");
    }

    @setter("tripId")
    public void setTripId(final IAgent agent, final int tripId) {
        agent.setAttribute("tripId", tripId);
    }

    // Getter for stopsInOrder
    @getter("stopsInOrder")
    public Object getStopsInOrder(final IAgent agent) {
        return agent.getAttribute("stopsInOrder");
    }

    // Getter for destination
    @getter("destination")
    public Object getDestination(final IAgent agent) {
        return agent.getAttribute("destination");
    }

    // Getter for predecessors
    @getter("predecessors")
    public Object getPredecessors(final IAgent agent) {
        return agent.getAttribute("predecessors");
    }
}
