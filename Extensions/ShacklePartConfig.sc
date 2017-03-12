ShacklePartConfig {

	// these vars have to be available globally because of the output methods
	var s_length, n_weight, s_chance, b_disable;
	var min_length = 30, max_length = 120; // initial min and max length
	var l_unsaved_changes;

*new
	{
	arg w_sub, part_spec, xpos, ypos, nbr_of_parts, max_length_abs;
	^super.new.initShacklePartConfig(w_sub, part_spec, xpos, ypos, nbr_of_parts, max_length_abs);
	}

initShacklePartConfig
	{
	arg w_sub, part_spec, xpos, ypos, nbr_of_parts, max_length_abs;

	var l_partname, v_min_length, v_max_length;
	var min_length_abs = 0; // range of the rangeslider
	var v_unsaved_changes = "<Unsaved changes>";
	var signal_color = Color.green(0.9);

	// extract the parameters from part_spec
	var partname = part_spec[0];
	var s_chance_init = Array.newClear(nbr_of_parts);
	var weight = part_spec[3];
	var disabled;

	if(max_length_abs.isNil, {max_length_abs = 300});

	min_length = part_spec[1];
	max_length = part_spec[2];

	s_chance_init.fill(0);

	if(isNil(part_spec[4]),
		{
		disabled = 0;
		},
		{
		disabled = 1;
		s_chance_init = part_spec[4];
		}
		);

//	part_spec.postln;

	// display data
	l_partname = StaticText(w_sub, Rect(10 + xpos,ypos,60,20));
	l_partname.string = partname;
	l_partname.font = Font("Helvetica",12, true);

	v_min_length = TextField(w_sub, Rect(75 + xpos, ypos, 50, 20));
	//v_min_length.setProperty(\boxColor,Color(85/255, 107/255, 47/255,0.7));
	v_min_length.value = min_length.asTimeStringHM;
	v_min_length.canFocus = false;

	s_length = RangeSlider(w_sub, Rect(125 + xpos, ypos,300,20));
	s_length.canFocus = false;
	s_length.knobColor = signal_color;
	s_length.lo = (min_length - min_length_abs) / (max_length_abs - min_length_abs);
	s_length.hi = (max_length - min_length_abs) / (max_length_abs - min_length_abs);
	s_length.action =
		{
		min_length =
			min_length_abs +
			(s_length.lo * (max_length_abs - min_length_abs)).floor;
		max_length =
			min_length_abs +
			(s_length.hi * (max_length_abs - min_length_abs)).floor;
		v_min_length.value = min_length.asTimeStringHM;
		v_max_length.value = max_length.asTimeStringHM;
		l_unsaved_changes.string = v_unsaved_changes;
		};

	v_max_length = TextField(w_sub, Rect(425 + xpos, ypos, 50, 20));
	//v_max_length.setProperty(\boxColor,Color(85/255, 107/255, 47/255,0.7));
	v_max_length.value = max_length.asTimeStringHM;
	v_max_length.canFocus = false;

	n_weight = NumberBox(w_sub, Rect(480 + xpos, ypos, 40, 20));
	//n_weight.canFocus = false;
	n_weight.scroll_step_(0.1);
	n_weight.clipLo_(0);
	n_weight.clipHi_(5);
	n_weight.value = weight;
	n_weight.action = {l_unsaved_changes.string = v_unsaved_changes};

	s_chance = MultiSliderView(w_sub, Rect(535 + xpos, ypos, (20.5 * nbr_of_parts), 25));
	s_chance.canFocus = false;
	s_chance.valueThumbSize_(5.0);
	s_chance.indexThumbSize_(19.3);
	s_chance.gap_(1);
	s_chance.fillColor_(signal_color);
	s_chance.strokeColor_(signal_color);
	s_chance.action = {l_unsaved_changes.string = v_unsaved_changes};
	s_chance.value_(s_chance_init);

	b_disable = Button(w_sub, Rect(550 + (20.5 * nbr_of_parts) + xpos, ypos, 20, 20));
	b_disable.states = [["X", Color.black, Color.white],["", Color.black, Color.white]];
	b_disable.canFocus = false;
	b_disable.value = disabled;
	b_disable.action = {l_unsaved_changes.string = v_unsaved_changes};

	l_unsaved_changes = StaticText(w_sub, Rect(600 + (19.5 * nbr_of_parts) + xpos, ypos, 90, 20));
	l_unsaved_changes.string = "";
	l_unsaved_changes.font = Font("Helvetica",9, true);

	}

minLen
	{
	^min_length.floor;
	}

maxLen
	{
	^max_length.floor;
	}

weight
	{
	^n_weight.value.round(0.01);
	}

disable
	{
	^b_disable.value;
	}

chances
	{
	arg nbr_of_parts;
	var chances = Array.newClear(nbr_of_parts);
	nbr_of_parts.do({ |i|
		chances[i] = s_chance.value[i].round(0.01);
	});
	^chances;
	}

saved_
	{
	l_unsaved_changes.string = "";
	}
}
