package gaml.additions.GTFS;

import gama.gaml.multi_criteria.*;
import gama.core.runtime.exceptions.*;
import java.lang.*;
import gama.gaml.descriptions.*;
import gama.core.outputs.layers.*;
import gama.gaml.architecture.user.*;
import gama.gaml.architecture.reflex.*;
import gama.gaml.statements.test.*;
import gama.core.util.*;
import gama.gaml.architecture.finite_state_machine.*;
import gama.gaml.types.*;
import  gama.core.metamodel.shape.*;
import gama.core.metamodel.shape.*;
import gama.core.outputs.layers.charts.*;
import gama.gaml.operators.*;
import gama.core.metamodel.population.*;
import gama.core.util.tree.*;
import gama.core.util.matrix.*;
import gama.gaml.compilation.*;
import gama.core.kernel.root.*;
import gama.gaml.factories.*;
import gama.gaml.skills.*;
import gama.core.util.path.*;
import gama.core.kernel.experiment.*;
import java.util.*;
import gama.gaml.statements.draw.*;
import gama.core.util.graph.*;
import gama.gaml.statements.*;
import gama.gaml.architecture.weighted_tasks.*;
import gama.core.kernel.model.*;
import gama.core.outputs.*;
import gama.core.metamodel.topology.*;
import gama.core.metamodel.agent.*;
import gama.gaml.expressions.*;
import gama.core.util.file.*;
import gama.core.kernel.batch.*;
import gama.gaml.species.*;
import gama.gaml.variables.*;
import gama.core.common.interfaces.*;
import gama.core.runtime.*;
import gama.core.messaging.*;
import gama.core.kernel.simulation.*;
import gama.gaml.operators.Random;
import gama.gaml.operators.Maths;
import gama.gaml.operators.Points;
import gama.gaml.operators.spatial.SpatialProperties;
import gama.gaml.operators.System;
import static gama.gaml.operators.Cast.*;
import gama.gaml.operators.spatial.*;
import static gama.core.common.interfaces.IKeyword.*;
@SuppressWarnings({ "rawtypes", "unchecked", "unused" })

public class GamlAdditions extends gama.gaml.compilation.AbstractGamlAdditions {
	public void initialize() throws SecurityException, NoSuchMethodException {
	initializeVars();
	initializeFile();
	initializeAction();
	initializeSkill();
}public void initializeVars()  {
_var(gama.extension.GTFS.skills.TransportStopSkill.class,desc(5,S("type","5","name","stops","of","11")),(s,a,t,v)->t==null? null:((gama.extension.GTFS.skills.TransportStopSkill)t).getStops(a),null,(s,a,t,v)->{if (t != null) ((gama.extension.GTFS.skills.TransportStopSkill) t).setStops(a, (IList) v); return null; });
}public void initializeFile() throws SecurityException, NoSuchMethodException {
_file("gtfs",gama.extension.GTFS.GTFS_reader.class,(s,o)-> {return new gama.extension.GTFS.GTFS_reader(s,((String)o[0]));},5,1,4,S("txt"));
_operator(S("is_gtfs"),null,"Returns true if the parameter is a gtfs file",I(0),B,true,3,0,0,0,(s,o)-> { return GamaFileType.verifyExtension("gtfs",Cast.asString(s, o[0]));}, false);
_operator(S("gtfs_file"),gama.extension.GTFS.GTFS_reader.class.getConstructor(SC,S),4,I(0),GF,false,"gtfs",(s,o)-> {return new gama.extension.GTFS.GTFS_reader(s,((String)o[0]));});
}public void initializeAction() throws SecurityException, NoSuchMethodException {
_action(new GamaHelper("loadStopsFromGTFS",gama.extension.GTFS.skills.TransportStopSkill.class,(s,a,t,v)->((gama.extension.GTFS.skills.TransportStopSkill) t).loadStopsFromGTFS(s)),desc(PRIM,new Children(_arg("filePath",4,F)),NAME,"loadStopsFromGTFS",TYPE,Ti(I),VIRTUAL,FALSE),gama.extension.GTFS.skills.TransportStopSkill.class.getMethod("loadStopsFromGTFS",SC));
}public void initializeSkill()  {
_skill("TransportStopSkill",gama.extension.GTFS.skills.TransportStopSkill.class,AS);
}
}