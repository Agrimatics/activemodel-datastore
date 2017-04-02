initializeNestedAttributes = (name) ->
  if $(".duplicatable_nested_#{name}_form").length
    forms_on_page = $(".duplicatable_nested_#{name}_form").length

    $('body').on 'click', ".destroy_nested_#{name}_form", (e) ->
      e.preventDefault()
      if $(".duplicatable_nested_#{name}_form:visible").length > 1
        $(this).closest(".duplicatable_nested_#{name}_form").slideUp().remove()

    $('body').on 'click', ".mark_nested_#{name}_form_as_destroyed", (e) ->
      e.preventDefault()
      form = $(this).closest(".duplicatable_nested_#{name}_form")
      form.find('input[id*="_destroy"]').val('true')
      form.slideUp().hide()

    $(".insert_nested_#{name}_form").on 'click', (e) ->
      e.preventDefault()
      last_nested_form = $(".duplicatable_nested_#{name}_form").last()
      new_nested_form = $(last_nested_form).clone(true)
      new_nested_form.show()
      forms_on_page += 1

      $(new_nested_form).find(".mark_nested_#{name}_form_as_destroyed").each ->
        $(this).toggleClass("mark_nested_#{name}_form_as_destroyed destroy_nested_#{name}_form")

      $(new_nested_form).find('label').each ->
        old_label = $(this).attr 'for'
        if old_label?
          new_label = old_label.replace(new RegExp(/_[0-9]+_/), "_#{forms_on_page - 1}_")
          $(this).attr 'for', new_label

      $(new_nested_form).find('select, input').each ->
        $(this).removeData()
        if $(this).is(':checkbox')
          $(this).prop('checked', false)
        else if $(this).is('select')
          $(this).find('option:eq(0)').prop('selected', true)
        else
          $(this).val('')
        old_id = $(this).attr 'id'
        if old_id?
          new_id = old_id.replace(new RegExp(/_[0-9]+_/), "_#{forms_on_page - 1}_")
          $(this).attr 'id', new_id

        old_name = $(this).attr 'name'
        new_name = old_name.replace(new RegExp(/\[[0-9]+]/), "[#{forms_on_page - 1}]")
        $(this).attr 'name', new_name

      $(new_nested_form).insertAfter(last_nested_form)
  else
    $('body').on 'click', ".destroy_nested_#{name}_form", (e) ->
      e.preventDefault()
    $('body').on 'click',".mark_nested_#{name}_form_as_destroyed", (e) ->
      e.preventDefault()
    $(".insert_nested_#{name}_form").on 'click', (e) ->
      e.preventDefault()
window.initializeNestedAttributes = initializeNestedAttributes
