import pf.Attribute
import pf.Html
import http.Response

## Shared document shell for the executable Datastar examples.
Page :: [].{

	document : Str, List(Html.Node) -> Html.Document
	document = |title, content|
		Html.render_document(
			Html.html(
				[Attribute.attribute("lang", "en")],
				[
					Html.head(
						[],
						[
							Html.meta([Attribute.attribute("charset", "utf-8")]),
							Html.meta([
								Attribute.name("viewport"),
								Attribute.attribute("content", "width=device-width, initial-scale=1"),
							]),
							Html.title([], [Html.text("${title} · Roc + Datastar")]),
							Html.element(
								"script",
								[Attribute.type("module"), Attribute.src("/datastar.js")],
								[],
							),
							Html.element(
								"style",
								[],
								[Html.dangerously_include_unescaped_html(styles)],
							),
						],
					),
					Html.body(
						[],
						List.concat(
							[
								Html.nav(
									[],
									[
										Html.a([Attribute.href("/")], [Html.text("All examples")]),
										Html.a(
											[
												Attribute.href("https://data-star.dev/examples/"),
												Attribute.rel("noreferrer"),
											],
											[Html.text("Datastar originals")],
										),
									],
								),
							],
							content,
						),
					),
				],
			),
		)

	response : Html.Document -> Response
	response = |document_value|
		Response.from_status(200)
			.with_headers([{ name: "Content-Type", value: "text/html; charset=utf-8" }])
			.with_body(document_value.to_bytes())

	text_response : U16, Str -> Response
	text_response = |status, body|
		Response.from_status(status)
			.with_headers([{ name: "Content-Type", value: "text/plain; charset=utf-8" }])
			.with_body(Str.to_utf8(body))
}

styles : Str
styles =
	\\:root { color-scheme: light dark; font-family: system-ui, sans-serif; }
	\\body { max-width: 54rem; margin: 3rem auto; padding: 0 1rem; }
	\\nav { display: flex; gap: 1rem; margin-bottom: 2rem; }
	\\fieldset { padding: 1.5rem; }
	\\input { width: min(24rem, 100%); padding: .65rem; }
	\\input[type="checkbox"] { width: auto; }
	\\button { margin: 1rem .5rem 0 0; padding: .65rem 1rem; }
	\\table { width: 100%; margin-top: 1rem; border-collapse: collapse; }
	\\th, td { text-align: left; padding: .5rem; border-bottom: 1px solid #8886; }
	\\code { background: #8882; padding: .1rem .3rem; }
	\\#throb { padding: 2rem; transition: color 1s, background-color 1s; }
