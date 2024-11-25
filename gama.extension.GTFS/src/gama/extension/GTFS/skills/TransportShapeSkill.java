package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.setter;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.core.metamodel.agent.IAgent;
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;
import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.IShape;
import gama.core.runtime.IScope;

import java.util.List;

@skill(name = "TransportShapeSkill", doc = @doc("Skill for agents representing transport shapes with a list of points."))
@vars({
    @variable(name = "shapeId", type = IType.INT, doc = @doc("The ID of the transport shape.")),
    @variable(name = "points", type = IType.LIST, of = IType.POINT, doc = @doc("The list of points composing the shape."))
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

    @getter("points")
    public List<GamaPoint> getPoints(final IAgent agent) {
        return (List<GamaPoint>) agent.getAttribute("points");
    }

    @setter("points")
    public void setPoints(final IAgent agent, final List<GamaPoint> points) {
        agent.setAttribute("points", points);
    }
    
    @getter("length")
    public double getLength(final IAgent agent) {
        List<GamaPoint> points = getPoints(agent);
        if (points.size() < 2) return 0;
        double length = 0;
        for (int i = 1; i < points.size(); i++) {
            length += points.get(i - 1).euclidianDistanceTo(points.get(i));
        }
        return length;
    }
}
