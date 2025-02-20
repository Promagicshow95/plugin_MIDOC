package gama.extension.GTFS.gaml;

import gama.core.runtime.IScope;
import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.population.IPopulation;
import gama.core.util.GamaListFactory;
import gama.core.util.GamaMapFactory;
import gama.core.util.GamaPair;
import gama.core.util.IList;
import gama.core.util.IMap;
import gama.extension.GTFS.TransportStop;
import gama.gaml.statements.CreateStatement;
import gama.gaml.statements.RemoteSequence;
import gama.gaml.types.Types;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class TransportStopCreator implements GTFSAgentCreator {
    private List<TransportStop> stops;

    public TransportStopCreator(List<TransportStop> stops) {
        this.stops = stops;
    }

    @Override
    public void addInits(IScope scope, List<Map<String, Object>> inits, Integer max) {
        int limit = (max != null) ? Math.min(max, stops.size()) : stops.size();

        for (int i = 0; i < limit; i++) {
            TransportStop stop = stops.get(i);
            Map<String, Object> stopInit = new HashMap<>();
            stopInit.put("stopId", stop.getStopId());
            stopInit.put("stopName", stop.getStopName());
            stopInit.put("location", stop.getLocation());
            stopInit.put("departureTripsInfo", stop.getDepartureTripsInfo());
            stopInit.put("name", stop.getStopName());
            inits.add(stopInit);
        }
    }

    @Override
    public IList<? extends IAgent> createAgents(IScope scope, IPopulation<? extends IAgent> population, List<Map<String, Object>> inits, CreateStatement statement, RemoteSequence sequence) {
        IList<? extends IAgent> createdAgents = population.createAgents(scope, inits.size(), inits, false, true);
        @SuppressWarnings("unchecked")
		IMap<String, IAgent> stopIdToAgentMap = GamaMapFactory.create(Types.STRING, Types.AGENT);

        for (IAgent agent : createdAgents) {
            String stopId = (String) agent.getAttribute("stopId");
            stopIdToAgentMap.put(stopId, agent);
        }

        for (IAgent agent : createdAgents) {
            @SuppressWarnings("unchecked")
			IMap<String, IList<GamaPair<String, String>>> departureTripsInfo =
                    (IMap<String, IList<GamaPair<String, String>>>) agent.getAttribute("departureTripsInfo");

            if (departureTripsInfo == null || departureTripsInfo.isEmpty()) {
                continue;
            }

            @SuppressWarnings("unchecked")
			IMap<String, IList<GamaPair<IAgent, String>>> departureStopsInfo = GamaMapFactory.create(Types.STRING, Types.LIST);
            for (Map.Entry<String, IList<GamaPair<String, String>>> entry : departureTripsInfo.entrySet()) {
                IList<GamaPair<IAgent, String>> convertedStops = GamaListFactory.create(Types.PAIR);
                for (GamaPair<String, String> pair : entry.getValue()) {
                    IAgent stopAgent = stopIdToAgentMap.get(pair.first());
                    if (stopAgent != null) {
                        convertedStops.add(new GamaPair<>(stopAgent, pair.getValue(), Types.AGENT, Types.STRING));
                    }
                }
                departureStopsInfo.put(entry.getKey(), convertedStops);
            }

            agent.setAttribute("departureStopsInfo", departureStopsInfo);
        }

        return createdAgents; 
    }

	@Override
	public boolean handlesCreation() {
		return true;
	}
}
