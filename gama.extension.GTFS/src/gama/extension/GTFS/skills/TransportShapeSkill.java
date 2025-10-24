package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.setter;
import gama.annotations.precompiler.GamlAnnotations.doc;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.Geometry;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.LineString;
import org.locationtech.jts.linearref.LengthIndexedLine;
import gama.core.metamodel.agent.IAgent;
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;

/**
 * Skill for transport shape agents.
 */
@skill(name = "TransportShapeSkill", doc = @doc("Skill for agents representing transport shapes with a polyline representation."))
@vars({
    @variable(name = "shapeId",  type = IType.STRING, doc = @doc("The ID of the transport shape.")),
    @variable(name = "routeType", type = IType.INT,    doc = @doc("The transport type associated with this shape.")),
    @variable(name = "routeId",   type = IType.STRING, doc = @doc("The route ID associated with this shape.")),
    @variable(name = "tripId",   type = IType.STRING,  doc = @doc("The trip ID associated with this shape."))
})
public class TransportShapeSkill extends Skill {

	@getter("shapeId") public String getShapeId(final IAgent agent) {
        return (String) agent.getAttribute("shapeId");
    }
    @setter("shapeId") public void setShapeId(final IAgent agent, final String shapeId) {
        agent.setAttribute("shapeId", shapeId);
    }
    
    @getter("routeType") public int getRouteType(final IAgent agent) {
        return (int) agent.getAttribute("routeType");
    }
    
    @setter("routeType") public void setRouteType(final IAgent agent, final int routeType) {
        agent.setAttribute("routeType", routeType);
    }
    
    @setter("routeId") public void setRouteId(final IAgent agent, final String routeId) {
        agent.setAttribute("routeId", routeId);
    }
    
    @getter("routeId") public String getRouteId(final IAgent agent) {
        return (String) agent.getAttribute("routeId");
    }
    
    @getter("tripId") public String getTripId(final IAgent agent) {
        return (String) agent.getAttribute("tripId");
    }

    @setter("tripId") public void setTripId(final IAgent agent, final String tripId) {
        agent.setAttribute("tripId", tripId);
    }



}