package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.setter;
import gama.annotations.precompiler.GamlAnnotations.doc;

import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.shape.GamaPoint; // ✅ Import essentiel
import gama.core.util.IList;
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;

/**
 * Skill for transport shape agents.
 */
@skill(name = "TransportShapeSkill", doc = @doc("Skill for agents representing transport shapes with a polyline representation."))
@vars({
    @variable(name = "shapeId", type = IType.INT, doc = @doc("The ID of the transport shape.")),
    @variable(name = "routeType", type = IType.INT, doc = @doc("The transport type associated with this shape (bus, tram, metro, etc.).")),
    @variable(name = "routeId", type = IType.STRING, doc = @doc("The route ID associated with this shape.")),
    @variable(name = "tripId", type = IType.INT, doc = @doc("The trip ID associated with this shape.")),
    @variable(name = "shape_points", type = IType.LIST, doc = @doc("List of GamaPoint objects representing the shape geometry."))
})
public class TransportShapeSkill extends Skill {

    @getter("shapeId")
    public int getShapeId(final IAgent agent) {
        return (int) agent.getAttribute("shapeId");
    }

    @setter("shapeId")
    public void setShapeId(final IAgent agent, final int shapeId) {
        agent.setAttribute("shapeId", shapeId);
    }

    @getter("routeType")
    public int getRouteType(final IAgent agent) {
        return (int) agent.getAttribute("routeType");
    }

    @setter("routeType")
    public void setRouteType(final IAgent agent, final int routeType) {
        agent.setAttribute("routeType", routeType);
    }

    @getter("routeId")
    public String getRouteId(final IAgent agent) {
        String routeId = (String) agent.getAttribute("routeId");
        System.out.println("[DEBUG] Retrieving routeId for agent: " + routeId);
        return routeId;
    }

    @setter("routeId")
    public void setRouteId(final IAgent agent, final String routeId) {
        System.out.println("[DEBUG] Storing routeId in agent: " + routeId);
        agent.setAttribute("routeId", routeId);
    }

    @getter("tripId")
    public int getTripId(final IAgent agent) {
        return (int) agent.getAttribute("tripId");
    }

    @setter("tripId")
    public void setTripId(final IAgent agent, final int tripId) {
        agent.setAttribute("tripId", tripId);
    }

    @SuppressWarnings("unchecked") // ✅ Supprime l'avertissement de cast
    @getter("shape_points")
    public IList<GamaPoint> getPoints(final IAgent agent) {
        return (IList<GamaPoint>) agent.getAttribute("shape_points");
    }
}
