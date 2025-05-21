package gama.extension.GTFS.Operators;

import gama.core.runtime.IScope;
import gama.core.util.GamaDate;
import gama.extension.GTFS.GTFS_reader;
import gama.gaml.types.IType;
import gama.annotations.precompiler.IOperatorCategory;
import gama.annotations.precompiler.GamlAnnotations.operator;


public class GTFSOperators {

	@operator(
		    value = "starting_date_gtfs",
		    type = IType.DATE,
		    category = { IOperatorCategory.DATE }
		)
		public static GamaDate starting_date_gtfs(final IScope scope, final GTFS_reader gtfs) {
		    java.time.LocalDate localDate = gtfs.getStartingDate();
		    if (localDate == null) return null;
		    return new GamaDate(scope, localDate);
		}

		@operator(
		    value = "ending_date_gtfs",
		    type = IType.DATE,
		    category = { IOperatorCategory.DATE }
		)
		public static GamaDate ending_date_gtfs(final IScope scope, final GTFS_reader gtfs) {
		    java.time.LocalDate localDate = gtfs.getEndingDate();
		    if (localDate == null) return null;
		    return new GamaDate(scope, localDate);
		}

}
