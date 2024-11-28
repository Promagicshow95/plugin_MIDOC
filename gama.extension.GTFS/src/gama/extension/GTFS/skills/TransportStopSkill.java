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
 * This skill stores attributes like stopId, stopName, and tripAssociations for each stop.
 */
@skill(name = "TransportStopSkill", doc = @doc("Skill for agents that represent individual transport stops with attributes like stopId, stopName, and tripAssociations."))
@vars({
    @variable(name = "stopId", type = IType.STRING, doc = @doc("The ID of the transport stop.")),
    @variable(name = "stopName", type = IType.STRING, doc = @doc("The name of the transport stop.")),
    @variable(name = "tripAssociations", type = IType.MAP, doc = @doc("A map of trip IDs to the list of predecessor stops (IList<TransportStop>).")),
    @variable(name = "tripHeadsigns", type = IType.MAP, doc = @doc("A map of trip IDs to their corresponding headsigns."))
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

    // Getter and setter for tripHeadsigns
    @SuppressWarnings("unchecked")
	@getter("tripHeadsigns")
    public IMap<Integer, String> getTripHeadsigns(final IAgent agent) {
        return (IMap<Integer, String>) agent.getAttribute("tripHeadsigns");
    }

    @setter("tripHeadsigns")
    public void setTripHeadsigns(final IAgent agent, final IMap<Integer, String> tripHeadsigns) {
        agent.setAttribute("tripHeadsigns", tripHeadsigns);
    }

    // Optional: Utility method to retrieve predecessors for a specific trip
    @getter("predecessors")
    public IList<IAgent> getPredecessorsForTrip(final IAgent agent, final int tripId) {
        IMap<Integer, IList<IAgent>> associations = getTripAssociations(agent);
        return associations != null ? associations.get(tripId) : null;
    }
}
