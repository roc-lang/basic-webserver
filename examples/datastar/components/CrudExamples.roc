import ./Page
import pf.Attribute
import pf.Datastar
import pf.Html
import pf.MultipartFormData
import pf.Server

EditSignals : { editEmail : Str, editName : Str }

ValidationSignals : { email : Str, firstName : Str, lastName : Str }

Contact : { email : Str, name : Str }

UploadedFile : { contents : Str, mime : Str, name : Str }

FileUploadSignals : { files : List(UploadedFile) }

## Finite request/response examples for editing, forms, uploads, and validation.
## Browser signals carry transient UI state, so these probes need no mutable
## process-local storage.
CrudExamples :: [].{

	respond! : Server.Request, Str => Try([Handled(Server.Outcome), NotHandled], [ServerErr(Str), ..])
	respond! = |request, path|
		match (request.method(), path) {
			(GET, "/examples/delete_row") => Ok(Handled(page("Delete Row", "Delete table rows after confirmation, then restore the original rows.", delete_row_demo, "DELETE responses remove one selected row; reset returns the complete table body.")))
			(DELETE, "/examples/delete_row/0") => Ok(Handled(delete_row(0)))
			(DELETE, "/examples/delete_row/1") => Ok(Handled(delete_row(1)))
			(DELETE, "/examples/delete_row/2") => Ok(Handled(delete_row(2)))
			(PUT, "/examples/delete_row/reset") => Ok(Handled(reset_delete_rows))

			(GET, "/examples/edit_row") => Ok(Handled(page("Edit Row", "Replace a selected table row with an inline editor.", edit_row_demo, "Finite GET and PUT actions swap one stable row between display and edit markup.")))
			(GET, "/examples/edit_row/0") => Ok(Handled(edit_row(0)))
			(GET, "/examples/edit_row/1") => Ok(Handled(edit_row(1)))
			(GET, "/examples/edit_row/2") => Ok(Handled(edit_row(2)))
			(GET, "/examples/edit_row/3") => Ok(Handled(edit_row(3)))
			(GET, "/examples/edit_row/0/cancel") => Ok(Handled(cancel_edit(0)))
			(GET, "/examples/edit_row/1/cancel") => Ok(Handled(cancel_edit(1)))
			(GET, "/examples/edit_row/2/cancel") => Ok(Handled(cancel_edit(2)))
			(GET, "/examples/edit_row/3/cancel") => Ok(Handled(cancel_edit(3)))
			(PUT, "/examples/edit_row/0") => save_edit!(request, 0).map_ok(|outcome| Handled(outcome))
			(PUT, "/examples/edit_row/1") => save_edit!(request, 1).map_ok(|outcome| Handled(outcome))
			(PUT, "/examples/edit_row/2") => save_edit!(request, 2).map_ok(|outcome| Handled(outcome))
			(PUT, "/examples/edit_row/3") => save_edit!(request, 3).map_ok(|outcome| Handled(outcome))
			(PUT, "/examples/edit_row/reset") => Ok(Handled(reset_edit_rows))

			(GET, "/examples/file_upload") => Ok(Handled(page("File Upload", "Upload one or more files smaller than the request limit.", file_upload_demo, "The pinned client encodes file names, MIME types, and Base64 contents in a bounded JSON signal document before the result is patched into the page.")))
			(POST, "/examples/file_upload") => upload_files!(request).map_ok(|outcome| Handled(outcome))

			(GET, "/examples/form_data") => Ok(Handled(page("Form Data", "Submit checkbox values as form-encoded GET or POST data.", form_data_demo, "Datastar selects form controls and the platform decodes the resulting URL-encoded query or request body.")))
			(GET, "/examples/form_data/data") => form_data!(request).map_ok(|outcome| Handled(outcome))
			(POST, "/examples/form_data/data") => form_data!(request).map_ok(|outcome| Handled(outcome))

			(GET, "/examples/inline_validation") => Ok(Handled(page("Inline Validation", "Validate three bound fields as the user types.", inline_validation_demo, "A bounded JSON signal document produces a finite status patch without replacing the inputs currently being edited.")))
			(POST, "/examples/inline_validation/validate") => validate_inline!(request).map_ok(|outcome| Handled(outcome))
			_ => Ok(NotHandled)
		}
}

page : Str, Str, Str, Str -> Server.Outcome
page = |title, description, demo_html, validation|
	Server.respond(
		Page.response(
			Page.document(
				title,
				[
					Html.h1([], [Html.text(title)]),
					Html.p([], [Html.text(description)]),
					Html.element(
						"fieldset",
						[],
						[
							Html.element("legend", [], [Html.text("Demo")]),
							Html.dangerously_include_unescaped_html(demo_html),
						],
					),
					Html.h2([], [Html.text("What this validates")]),
					Html.p([], [Html.text(validation)]),
				],
			),
		),
	)

contacts : List(Contact)
contacts = [
	{ name: "Joe Smith", email: "joe@smith.org" },
	{ name: "Angie MacDowell", email: "angie@macdowell.org" },
	{ name: "Fuqua Tarkenton", email: "fuqua@tarkenton.org" },
	{ name: "Kim Yee", email: "kim@yee.org" },
]

contact_at : U64 -> Contact
contact_at = |index| List.get(contacts, index) ?? { name: "Unknown", email: "unknown@example.com" }

delete_row_demo : Str
delete_row_demo =
	Html.render_without_doc_type(
		Html.div(
			[Attribute.id("delete-row-demo"), Attribute.attribute("data-signals:_fetching__ifmissing", "false")],
			[
				Html.table(
					[],
					[
						Html.thead([], [Html.tr([], [Html.th([], [Html.text("Name")]), Html.th([], [Html.text("Email")]), Html.th([], [Html.text("Actions")])])]),
						Html.tbody([Attribute.id("delete-row-body")], delete_rows),
					],
				),
				Html.button(
					[Attribute.attribute("data-action", "reset-delete-rows"), Attribute.attribute("data-on:click", "@put('/examples/delete_row/reset')")],
					[Html.text("Reset")],
				),
			],
		),
	)

delete_rows : List(Html.Node)
delete_rows = List.map([0, 1, 2], delete_row_node)

delete_row_node : U64 -> Html.Node
delete_row_node = |index| {
	contact = contact_at(index + 1)
	Html.tr(
		[Attribute.id("delete-row-${U64.to_str(index)}")],
		[
			Html.td([], [Html.text(contact.name)]),
			Html.td([], [Html.text(contact.email)]),
			Html.td(
				[],
				[
					Html.button(
						[
							Attribute.attribute("data-delete-row", U64.to_str(index)),
							Attribute.attribute("data-on:click", "confirm('Are you sure?') && @delete('/examples/delete_row/${U64.to_str(index)}')"),
						],
						[Html.text("Delete")],
					),
				],
			),
		],
	)
}

delete_row : U64 -> Server.Outcome
delete_row = |index| Datastar.respond([Datastar.remove_elements("#delete-row-${U64.to_str(index)}")])

reset_delete_rows : Server.Outcome
reset_delete_rows = Datastar.respond([Datastar.patch_elements(Html.render_without_doc_type(Html.tbody([Attribute.id("delete-row-body")], delete_rows)))])

edit_row_demo : Str
edit_row_demo =
	Html.render_without_doc_type(
		Html.div(
			[Attribute.id("edit-row-demo"), Attribute.attribute("data-signals:_fetching__ifmissing", "false")],
			[
				Html.table(
					[],
					[
						Html.thead([], [Html.tr([], [Html.th([], [Html.text("Name")]), Html.th([], [Html.text("Email")]), Html.th([], [Html.text("Actions")])])]),
						Html.tbody([Attribute.id("edit-row-body")], List.map([0, 1, 2, 3], display_edit_row)),
					],
				),
				Html.button(
					[Attribute.attribute("data-action", "reset-edit-rows"), Attribute.attribute("data-on:click", "@put('/examples/edit_row/reset')")],
					[Html.text("Reset")],
				),
			],
		),
	)

display_edit_row : U64 -> Html.Node
display_edit_row = |index| display_edit_row_with(index, contact_at(index))

display_edit_row_with : U64, Contact -> Html.Node
display_edit_row_with = |index, contact|
	Html.tr(
		[Attribute.id("edit-row-${U64.to_str(index)}")],
		[
			Html.td([Attribute.attribute("data-edit-name", U64.to_str(index))], [Html.text(contact.name)]),
			Html.td([Attribute.attribute("data-edit-email", U64.to_str(index))], [Html.text(contact.email)]),
			Html.td(
				[],
				[
					Html.button(
						[Attribute.attribute("data-edit-row", U64.to_str(index)), Attribute.attribute("data-on:click", "@get('/examples/edit_row/${U64.to_str(index)}')")],
						[Html.text("Edit")],
					),
				],
			),
		],
	)

edit_row : U64 -> Server.Outcome
edit_row = |index| {
	contact = contact_at(index)
	row =
		Html.tr(
			[
				Attribute.id("edit-row-${U64.to_str(index)}"),
				Attribute.attribute("data-signals", Json.to_str({ editName: contact.name, editEmail: contact.email })),
			],
			[
				Html.td([], [Html.input([Attribute.attribute("data-bind:edit-name", "")])]),
				Html.td([], [Html.input([Attribute.attribute("data-bind:edit-email", "")])]),
				Html.td(
					[],
					[
						Html.button([Attribute.attribute("data-action", "save-edit-${U64.to_str(index)}"), Attribute.attribute("data-on:click", "@put('/examples/edit_row/${U64.to_str(index)}')")], [Html.text("Save")]),
						Html.button([Attribute.attribute("data-action", "cancel-edit-${U64.to_str(index)}"), Attribute.attribute("data-on:click", "@get('/examples/edit_row/${U64.to_str(index)}/cancel')")], [Html.text("Cancel")]),
					],
				),
			],
		)
	Datastar.respond([Datastar.patch_elements(Html.render_without_doc_type(row))])
}

cancel_edit : U64 -> Server.Outcome
cancel_edit = |index| Datastar.respond([Datastar.patch_elements(Html.render_without_doc_type(display_edit_row(index)))])

save_edit! : Server.Request, U64 => Try(Server.Outcome, [ServerErr(Str), ..])
save_edit! = |request, index| {
	parsed : Try(EditSignals, Datastar.SignalsError)
	parsed = Datastar.read_signals!(request)
	signals =
		match parsed {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(Page.text_response(400, "Invalid Edit Row signals: ${Str.inspect(err)}")))
		}
	contact = { name: signals.editName, email: signals.editEmail }
	Ok(Datastar.respond([Datastar.patch_elements(Html.render_without_doc_type(display_edit_row_with(index, contact)))]))
}

reset_edit_rows : Server.Outcome
reset_edit_rows = Datastar.respond([Datastar.patch_elements(Html.render_without_doc_type(Html.tbody([Attribute.id("edit-row-body")], List.map([0, 1, 2, 3], display_edit_row))))])

file_upload_demo : Str
file_upload_demo =
	\\<div id="file-upload-demo">
	\\    <label><span>Pick anything less than 1 MiB</span><input id="file-upload-input" type="file" data-bind:files multiple></label>
	\\    <button data-action="upload-files" data-on:click="$files.length && @post('/examples/file_upload')" data-attr:disabled="!$files.length">Submit</button>
	\\    <div id="file-upload" hidden></div>
	\\</div>

upload_files! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
upload_files! = |request| {
	parsed : Try(FileUploadSignals, Datastar.SignalsError)
	parsed = Datastar.read_signals_with_limit!(request, 2 * 1024 * 1024)
	signals =
		match parsed {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(Page.text_response(400, "Invalid File Upload signals: ${Str.inspect(err)}")))
		}
	names = Str.join_with(List.map(signals.files, |file| file.name), ", ")
	result =
		Html.div(
			[Attribute.id("file-upload")],
			[Html.text("Received ${U64.to_str(List.len(signals.files))} file(s): ${names}.")],
		)
	Ok(Datastar.respond([Datastar.patch_elements(Html.render_without_doc_type(result))]))
}

form_data_demo : Str
form_data_demo =
	\\<div id="form-data-demo">
	\\    <form id="form-data-form">
	\\        <label>foo <input type="checkbox" name="checkboxes" value="foo"></label>
	\\        <label>bar <input type="checkbox" name="checkboxes" value="bar"></label>
	\\        <label>baz <input type="checkbox" name="checkboxes" value="baz"></label>
	\\        <button data-action="form-get" data-on:click="@get('/examples/form_data/data', {contentType: 'form'})">Submit GET request</button>
	\\        <button data-action="form-post" data-on:click="@post('/examples/form_data/data', {contentType: 'form'})">Submit POST request</button>
	\\    </form>
	\\    <button data-action="form-external" data-on:click="@get('/examples/form_data/data', {contentType: 'form', selector: '#form-data-form'})">Submit GET request from outside the form</button>
	\\    <div id="form-data-result"></div>
	\\</div>

form_data! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
form_data! = |request| {
	bytes =
		match request.method() {
			GET =>
				match request.target() {
					Resource({ raw_query: Present(query), .. }) => Str.to_utf8(query)
					_ => []
				}
			POST => request.body().with_limit(64 * 1024).read_all!() ? |err| ServerErr("Failed to read Form Data body: ${Str.inspect(err)}")
			_ => []
		}
	values =
		match MultipartFormData.parse_form_url_encoded(bytes) {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(Page.text_response(400, "Invalid Form Data body: ${Str.inspect(err)}")))
		}
	selection = Dict.get(values, "checkboxes") ?? "none"
	result = Html.div([Attribute.id("form-data-result")], [Html.text("Received checkbox value: ${selection}")])
	Ok(Datastar.respond([Datastar.patch_elements(Html.render_without_doc_type(result))]))
}

inline_validation_demo : Str
inline_validation_demo =
	\\<div id="inline-validation-demo" data-signals="{email: '', firstName: '', lastName: ''}">
	\\    <label>Email Address <input id="validation-email" type="email" required data-bind:email data-on:input__debounce.200ms="@post('/examples/inline_validation/validate')"></label>
	\\    <label>First Name <input id="validation-first-name" type="text" required data-bind:first-name data-on:input__debounce.200ms="@post('/examples/inline_validation/validate')"></label>
	\\    <label>Last Name <input id="validation-last-name" type="text" required data-bind:last-name data-on:input__debounce.200ms="@post('/examples/inline_validation/validate')"></label>
	\\    <div id="inline-validation-status"><p>Enter test@test.com and both names.</p><button id="validation-submit" aria-disabled="true">Sign Up</button></div>
	\\</div>

validate_inline! : Server.Request => Try(Server.Outcome, [ServerErr(Str), ..])
validate_inline! = |request| {
	parsed : Try(ValidationSignals, Datastar.SignalsError)
	parsed = Datastar.read_signals!(request)
	signals =
		match parsed {
			Ok(value) => value
			Err(err) => return Ok(Server.respond(Page.text_response(400, "Invalid Inline Validation signals: ${Str.inspect(err)}")))
		}
	email_valid = signals.email == "test@test.com"
	names_valid = Bool.not(Str.is_empty(signals.firstName)) and Bool.not(Str.is_empty(signals.lastName))
	valid = email_valid and names_valid
	message =
		if valid {
			"All fields are valid."
		} else if Bool.not(email_valid) {
			"Email must be test@test.com."
		} else {
			"First and last name are required."
		}
	status =
		Html.div(
			[Attribute.id("inline-validation-status")],
			[
				Html.p(
					[
						Attribute.attribute(
							"data-validation-result",
							if valid {
								"valid"
							} else {
								"invalid"
							},
						),
					],
					[Html.text(message)],
				),
				Html.button(
					[
						Attribute.id("validation-submit"),
						Attribute.attribute(
							"aria-disabled",
							if valid {
								"false"
							} else {
								"true"
							},
						),
					],
					[Html.text("Sign Up")],
				),
			],
		)
	Ok(Datastar.respond([Datastar.patch_elements(Html.render_without_doc_type(status))]))
}
