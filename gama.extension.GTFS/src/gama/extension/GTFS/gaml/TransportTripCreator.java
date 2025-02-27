package gama.extension.GTFS.gaml;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.population.IPopulation;
import gama.core.runtime.IScope;
import gama.core.util.IList;
import gama.extension.GTFS.TransportTrip;
import gama.gaml.statements.CreateStatement;
import gama.gaml.statements.RemoteSequence;

public class TransportTripCreator implements GTFSAgentCreator {
	
	@SuppressWarnings("unused")
	private List<TransportTrip> trips;
	
	public TransportTripCreator(List<TransportTrip> trips) {
		this.trips = (trips != null) ? trips : new ArrayList<>();
	}


	@Override
	public void addInits(IScope scope, List<Map<String, Object>> inits, Integer max) {
	    int limit = (max != null) ? Math.min(max, trips.size()) : trips.size();

	    for (int i = 0; i < limit; i++) {
	        TransportTrip trip = trips.get(i);
	        
	        Map<String, Object> tripInit = new HashMap<>();
	        tripInit.put("tripId", trip.getTripId());
	        tripInit.put("routeId", trip.getRouteId());
	        tripInit.put("stopsInOrder", trip.getStopsInOrder());
	        tripInit.put("destination", trip.getDestination());
	        tripInit.put("stopDetails", trip.getStopDetails());
	        tripInit.put("routeType", trip.getRouteType()); // ✅ Ajout de routeType

	        inits.add(tripInit);
	    }
	}

	@Override
	public boolean handlesCreation() {
	
		return false;
	}

	@Override
	public IList<? extends IAgent> createAgents(IScope scope, IPopulation<? extends IAgent> population,
			List<Map<String, Object>> inits, CreateStatement statement, RemoteSequence sequence) {
		
		return population.createAgents(scope, inits.size(), inits, false, true);
	}

}
