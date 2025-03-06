package gama.extension.GTFS.gaml;

import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.population.IPopulation;
import gama.core.metamodel.shape.IShape;
import gama.core.runtime.IScope;
import gama.core.util.IList;
import gama.extension.GTFS.TransportShape;
import gama.gaml.statements.CreateStatement;
import gama.gaml.statements.RemoteSequence;
import gama.core.common.interfaces.IKeyword;


import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class TransportShapeCreator implements GTFSAgentCreator {
	
	private List<TransportShape> shapes;

	/** Constructor with a list of shapes **/
	public TransportShapeCreator(List<TransportShape> shapes) {
		this.shapes = (shapes != null) ? shapes : new ArrayList<>();
	}

	@Override
	public void addInits(IScope scope, List<Map<String, Object>> inits, Integer max) {
	    int limit = (max != null) ? Math.min(max, shapes.size()) : shapes.size();

	    for (int i = 0; i < limit; i++) {
	        TransportShape shape = shapes.get(i);
	        IShape polyline = shape.generateShape(scope);

	        if (polyline == null) {
	            System.err.println("[ERROR] Shape generation failed for Shape ID: " + shape.getShapeId());
	            continue;
	        }

	        int routeType = shape.getRouteType();
	        String routeId = shape.getRouteId(); // Vérifier routeId ici

	        System.out.println("[DEBUG] Adding to inits: ShapeId=" + shape.getShapeId() + " RouteId=" + routeId);

	        final Map<String, Object> map = polyline.getAttributes(true);
	        polyline.setAttribute(IKeyword.SHAPE, polyline); 
	        map.put("shapeId", shape.getShapeId());
	        map.put("routeType", routeType);
	        map.put("routeId", shape.getRouteId()); 
	        inits.add(map);
	    }
	}

	@Override
	public IList<? extends IAgent> createAgents(IScope scope, IPopulation<? extends IAgent> population, List<Map<String, Object>> inits, CreateStatement statement, RemoteSequence sequence) {
	    throw new UnsupportedOperationException("createAgents() should not be called on TransportShapeCreator.");
	}
	
	@Override
	public boolean handlesCreation() {
	    return false; 
	}
}
