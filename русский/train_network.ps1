# LoRA retard-friendly train_network script v1.06 by anon
# Последнее обновление: 21.01.23 01:09 по МСК
# https://github.com/cloneofsimo/lora
# https://github.com/kohya-ss/sd-scripts
# https://rentry.org/2chAI_LoRA_Dreambooth_guide
param([int]$ChainedRun = 0, [int]$TestRun = 0)

<# ##### Начало конфига ##### #>
# Пути
$sd_scripts_dir = "X:\git-repos\sd-scripts\" # Путь к папке с репозиторием kohya-ss/sd-scripts
$ckpt = "X:\SD-models\checkpoint.safetensors" # Путь к чекпоинту (ckpt / safetensors)
$is_sd_v2_ckpt = 0 # Поставь '1' если загружаешь SD 2.x чекпоинт
$is_sd_v2_768_ckpt = 0 # Также поставь здесь значение '1', если загружаешь SD 2.x-768 чекпоинт
$image_dir = "X:\training_data\img\" # Путь к папке с изображениями. Внутри должны находится папки вида N_ConceptName
$output_dir = "X:\LoRA\" # Директория сохранения LoRA чекпоинтов
$output_name = "" # Название файла (расширение не нужно)

# (опционально) Дополнительные пути
$reg_dir = "" # Путь к папке с регуляризационными изображениями
$vae_path = "" # Путь к VAE

# Основные настройки
$max_train_epochs = 10 # Число эпох. Не имеет силы при $desired_training_time > 0
$max_train_steps = 0 # (опционально) Выставьте своё количество шагов обучения. desired_training_time и max_train_epochs должны быть равны нулю чтобы эта переменная имела силу
$train_batch_size = 1 # Количество изображений, на которых идёт обучение, одновременно
                      # Чем больше значение, тем меньше шагов обучения (обучение проходит быстрее), но больше потребление видеопамяти
$resolution = 512 # Разрешение обучения (пиксели)
$save_every_n_epochs = 1 # Сохранять чекпоинт каждые N эпох
$save_last_n_epochs = 999 # Сохранить только последние N эпох
$max_token_length = 75 # Максимальная длина токена. Возможные значения: 75 / 150 / 225
$clip_skip = 1 # Использовать вывод текстового энкодера с конца N-ного слоя

# (опционально) Время тренировки
$desired_training_time = 0 # Если значение выше 0, игнорировать количество изображений с повторениями при вычислении количества шагов и обучать сеть в течении N минут
$gpu_training_speed = "1.23it/s | 1.23s/it" # Средняя скорость тренировки, учитывая мощность GPU. Значение вида XX.XXit/s или XX.XXs/it

# Настройки обучения
$learning_rate = 1e-4 # Скорость обучения
$unet_lr = $learning_rate # Скорость обучения U-Net
$text_encoder_lr = $learning_rate # Скорость обучения текстового энкодера
$scheduler = "linear" # Планировщик скорости обучения. Возможные значения: linear, cosine, cosine_with_restarts, polynomial, constant (по умолчанию), constant_with_warmup
$lr_warmup_ratio = 0.0 # Отношение количества шагов разогрева планировщика к количеству шагов обучения (от 0 до 1). Не имеет силы при планировщике constant
$network_dim = 128 # Размер нетворка. Чем больше значение, тем больше точность и размер выходного файла
$is_random_seed = 1 # Сид обучения. 1 = рандомный сид, 0 = статичный
$shuffle_caption = 1 # Перетасовывать ли теги в файлах описания, разделённых запятой
$keep_tokens = 0 # Не перетасовывать первые N токенов при перемешивании описаний

# Последовательный запуск скриптов
# Здесь указываются пути, в которых находятся скрипты для последовательного выполнения
# Путей может быть сколько угодно
$script_paths = @(
	"<X:\Путь\к\скрипту\скрипт.ps1>",
	"<.\скрипт.ps1>",
	"<скрипт.ps1>"
)

# Дополнительные настройки
$gradient_checkpointing = 0 # https://huggingface.co/docs/transformers/perf_train_gpu_one#gradient-checkpointing
$gradient_accumulation_steps = 1 # https://huggingface.co/docs/transformers/perf_train_gpu_one#gradient-accumulation
$max_data_loader_n_workers = 8 # Максимальное количество потоков процессора для DataLoader
                               # Чем меньше значение, тем меньше потребление RAM, быстрее старт эпохи и медленнее загрузка данных
							   # Маленькое значение может негативно сказаться на скорости обучения
$save_precision = "fp16" # Использовать ли пользовательскую точность сохранения, и её тип. Возможные значения: no, float, fp16, bf16
$mixed_precision = "fp16" # Использовать ли смешанную точность для обучения, и её тип. Возможные значения: no, fp16, bf16
$do_not_interrupt = 0 # Не прерывать работу скрипта вопросами. По умолчанию включен если выполняется цепочка скриптов
$logging_dir = "" # (опционально) Папка для логов
$log_prefix = $output_name
$debug_dataset = 0

# Остальные настройки
$test_run = 0 # Не запускать основной скрипт
$do_not_clear_host = 1 # Не очищать консоль при запуске скрипта
$dont_draw_flags = 0 # Не рисовать флаги
<# ##### Конец конфига ##### #>

[console]::OutputEncoding = [text.encoding]::UTF8
$current_version = "1.06"
if ($do_not_clear_host -le 0) { Clear-Host } 

function Is-Numeric ($value) { return $value -match "^[\d\.]+$" }
function WCO($BackgroundColor, $ForegroundColor, $NewLine) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args)
	{
		if ($NewLine -eq 1) { Write-Host $args -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor -NoNewLine }
		else { Write-Output $args }
	}
    else { $input | Write-Output } 
	$host.UI.RawUI.ForegroundColor = $fc
}
function Word-Ending($value) {
	$ending = $value.ToString()
	if ($ending -ge "11" -and $ending -le "19") { return "й" }
	$ending = $ending.Substring([Math]::Max($ending.Length, 0) - 1)
	if ($ending -eq "1") { return "е" }
	if ($ending -ge "2" -and $ending -le "4") { return "я" }
	if (($ending -ge "5" -and $ending -le "9") -or $ending -eq "0") { return "й" } }
function Get-Changelog {
	$changelog_link = "https://raw.githubusercontent.com/anon-1337/LoRA-scripts/main/русский/script_changelog.txt"
	$changelog = (Invoke-WebRequest -Uri $changelog_link).Content | Out-String
	$changelog = $changelog -split "\r?\n"
	$max_version = "0.0"
	$last_version_string_index = 0; $index = 0
	foreach ($line in $changelog) {
		if ($line -match "`#+ v\d+[\.,]\d+") { $max_version = [float]($line -replace "^#+ +v"); $last_version_string_index = $index }
		$index += 1
	}
	$max_version_date = $changelog[$last_version_string_index + 1] -replace "#+ +"
	if ($max_version -gt $current_version) {
		Write-Output ""
		Write-Output "Полный ченджлог:"
		WCO black blue 0 "$changelog_link `n"
		Write-Output "Изменения в v${max_version} от ${max_version_date}:"
		while (($last_version_string_index + 3) -le $changelog.Length) { Write-Output "$($changelog[$last_version_string_index + 2])"; $last_version_string_index += 1 }
	}
}

# austism
if ($dont_draw_flags -le 0) {
$strl = 0
$version_string = "RetardScript v$current_version"
$version_string_length = $version_string.Length
while ($strl -lt ($([system.console]::BufferWidth))) { $strl += 1; WCO white white 1 " " }; Write-Output ""; $strl = 0; while ($version_string_length -lt $(($([system.console]::BufferWidth) + $version_string.Length) / 2)) { WCO darkred white 1 " "; $version_string_length += 1 }; WCO darkred white 1 $version_string; $version_string_length = $version_string.Length; while ($version_string_length -lt $(($([system.console]::BufferWidth) + $version_string.Length) / 2 - $version_string.Length % 2 + $([system.console]::BufferWidth) % 2)) { WCO darkred white 1 " "; $version_string_length += 1 }; while ($strl -lt ($([system.console]::BufferWidth))) { $strl += 1; WCO white white 1 " " } }

Write-Output " "
Write-Output "Если что-то не работает или работает не так, писать сюда:"
WCO black blue 0 "https://github.com/anon-1337/LoRA-scripts/issues"
Write-Output " "

# updater
$internet_available = 0
$script_origin = (get-location).path
Get-NetConnectionProfile | foreach { if ($_.IPv4Connectivity -eq "Internet") { $internet_available = 1 } }
sleep 1
if ($internet_available -eq 1 -and $TestRun -le 0 -and $ChainedRun -eq 0 -and $do_not_interrupt -le 0) {
	$script_url = "https://raw.githubusercontent.com/anon-1337/LoRA-scripts/main/русский/train_network.ps1"
	$script_github = (Invoke-WebRequest -Uri $script_url).Content | Out-String -Stream
	$script_github = $script_github -Split "\r?\n"
	$new_version = [float]$($script_github[$script_github.Length - 1] -replace "#[a-zA-Z=]+")
	if ([float]$current_version -lt $new_version -and (Is-Numeric $new_version)) { 
		Write-Output "Доступно обновление скрипта (v$current_version => v$new_version) по адресу:"
		WCO black blue 0 $script_url
		Get-Changelog
		$stopwatch = New-Object -TypeName System.Diagnostics.Stopwatch
		$stopwatch.Start()
		do { $do_update = Read-Host "Выполнить обновление? Внимание: файл будет перезаписан (y/N)" }
		until ($stopwatch.Elapsed.Seconds -ge 5 -or $do_update -eq "y" -or $do_update -ceq "N")
		if ($do_update -eq "y") {
			$restart = 1
			Set-Location -Path $script_origin
			curl -s $script_url -o "$PSCommandPath"
			WCO black green 0 "Обновлено до версии v$new_version!"
			Write-Output "Перезапуск..."
			sleep 2 }
	}
}

if ($restart -ne 1) {

$total = 0
$is_structure_wrong = 0
$abort_script = 0
$iter = 0

# paths check
Write-Output "Проверка путей..."
$all_paths = @( $sd_scripts_dir, $ckpt, $image_dir )
if ($reg_dir -ne "") { $all_paths += $reg_dir }
if ($use_vae -ge 1) { $all_paths += $vae_path }
foreach ($path in $all_paths) {
	if ($path -ne "" -and !(Test-Path $path)) {
		$is_structure_wrong = 1
		Write-Output "Путь $path не существует" } }

if ($is_chained_run -ge 1) { $do_not_interrupt = 1 }

# images
if ($is_structure_wrong -eq 0) { Get-ChildItem -Path $image_dir -Directory | ForEach-Object {
	if ($iter -eq 0) { Write-Output "Подсчет количества изображений в папках" }
    $parts = $_.Name.Split("_")
    if (!(Is-Numeric $parts[0]))
    {
		WCO black red 0 "Ошибка в $($_):`n`t$($parts[0]) не является числом"
		$is_structure_wrong = 1
        return
    }
	if ([int]$parts[0] -le 0)
	{
		WCO black red 0 "Ошибка в $($_):`nПовторения в имени папки с изображениями должно быть >0"
		$is_structure_wrong = 1
        return
	}
    $repeats = [int]$parts[0]
    $imgs = Get-ChildItem $_.FullName -Depth 0 -File -Include *.jpg, *.png, *.webp | Measure-Object | ForEach-Object { $_.Count }
	if ($iter -eq 0) { Write-Output "Обучающие изображения:" }
    $img_repeats = ($repeats * $imgs)
    Write-Output "`t$($parts[1]): $repeats повторени$(Word-Ending $repeats) * $imgs изображени$(Word-Ending $imgs) = $($img_repeats)"
    $total += $img_repeats
	$iter += 1
} }

$iter = 0

# regs
if ($is_structure_wrong -eq 0 -and $reg_dir -ne "") { Get-ChildItem -Path $reg_dir -Directory | % { if ($abort_script -ne "y") { ForEach-Object {
    $parts = $_.Name.Split("_")
    if (!(Is-Numeric $parts[0]))
    {
		WCO black red 0 "Ошибка в $($_):`n`t$($parts[0]) не является числом"
		$is_structure_wrong = 1
        return
    }
	if ([int]$parts[0] -le 0)
	{
		WCO black red 0 "Ошибка в $($_):`nПовторения в имени папки с изображениями должно быть >0"
		$is_structure_wrong = 1
        return
	}
    $repeats = [int]$parts[0]
    $reg_imgs = Get-ChildItem $_.FullName -Depth 0 -File -Include *.jpg, *.png, *.webp | Measure-Object | ForEach-Object { $_.Count }
	if ($iter -eq 0) { Write-Output "Регуляризационные изображения:" }
	if ($reg_imgs -eq 0 -and $do_not_interrupt -le 0) {
		WCO black darkyellow 0 "Внимание: папка для регуляризационных изображений присутствует, но в ней ничего нет"
		do { $abort_script = Read-Host "Прервать выполнение скрипта? (y/N)" }
		until ($abort_script -eq "y" -or $abort_script -ceq "N")
		return }
	else {
		$img_repeats = ($repeats * $reg_imgs)
		Write-Output "`t$($parts[1]): $repeats повторени$(Word-Ending $repeats) * $reg_imgs изображени$(Word-Ending $reg_imgs) = $($img_repeats)"
		$iter += 1 }
} } } }



if ($is_structure_wrong -eq 0 -and $abort_script -ne "y")
{
	Write-Output "Количество обучающих изображений с повторениями: $total"
	
	# steps
	if ($desired_training_time -gt 0) {
		Write-Output "desired_training_time > 0"
		Write-Output "Используем desired_training_time для вычисления шагов обучения, учитывая скорость GPU"
		if ($gpu_training_speed -match '^(?:\d+\.\d+|\d+|\.\d+)(?:(?:it|s)(?:\\|\/)(?:it|s))')
		{
			$speed_value = $gpu_training_speed -replace '[^.0-9]'
			if ([regex]::split($gpu_training_speed, '[\/\\]') -replace '\d+.\d+' -eq 's') { $speed_value = 1 / $speed_value }
			$max_train_steps = [float]$speed_value * 60 * $desired_training_time
			if ($reg_imgs -gt 0) {
				$max_train_steps *= 2
				$max_train_steps = [int]([math]::Round($max_train_steps))
				Write-Output "Количество регуляризационных изображений больше 0"
				if ($do_not_interrupt -le 0) { do { $reg_img_compensate_time = Read-Host "Вы хотите уменьшить количество шагов вдвое для компенсации увеличенного времени? (y/N)" }
				until ($reg_img_compensate_time -eq "y" -or $reg_img_compensate_time -ceq "N") }
				if ($reg_img_compensate_time -eq "y" -or $do_not_interrupt -ge 1) {
					$max_train_steps = [int]([math]::Round($max_train_steps / 2))
					WCO black gray 1 "Количество шагов: $([math]::Round($($speed_value * 60), 2)) it/min * $desired_training_time минут(-а) ≈ "; WCO white black 1 "$max_train_steps`n" }
				else {
					Write-Output "Вы выбрали нет. Увеличенное время компенсировано не будет, длительность тренировки увеличена вдвое"
					WCO black gray 1 "Количество шагов: $([math]::Round($($speed_value * 60), 2)) it/min * $desired_training_time минут(-а) * 2 ≈ "; WCO white black 1 "$max_train_steps`n" }
			}
			else {
				$max_train_steps = [int]([math]::Round($max_train_steps))
				WCO black gray 1 "Количество шагов: $([math]::Round($($speed_value * 60), 2)) it/min * $desired_training_time минут(-а) ≈ "; WCO white black 1 "$max_train_steps`n" }
		}
		else {
			WCO black red 0 "Неверно указана скорость обучения gpu_training_speed!"
			$abort_script = "y" }
	}
	elseif ($max_train_epochs -ge 1) {
		Write-Output "Используем количество изображений для вычисления шагов обучения"
		Write-Output "Количество эпох: $max_train_epochs"
		Write-Output "Размер обучающей партии (train_batch_size): $train_batch_size"
		if ($reg_imgs -gt 0)
		{
			$total *= 2
			Write-Output "Количество регуляризационных изображений больше 0: количество шагов будет увеличено вдвое"
		}
		$max_train_steps = [int]($total / $train_batch_size * $max_train_epochs)
		WCO black gray 1 "Количество шагов: $total / $train_batch_size * $max_train_epochs = "; WCO white black 1 "$max_train_steps`n"
	}
	else {
		Write-Output "Используем пользовательское количество шагов обучения"
		WCO black gray 1 "Количество шагов: "; WCO white black 1 "$max_train_steps`n"
	}
	
	# run parameters
	$run_parameters = "--network_module=networks.lora --train_data_dir=`"$image_dir`""
	
	# paths
	$image_dir = $image_dir.TrimEnd("\", "/")
	$reg_dir = $reg_dir.TrimEnd("\", "/")
	$output_dir = $output_dir.TrimEnd("\", "/")
	$logging_dir = $logging_dir.TrimEnd("\", "/")
	if ($reg_dir -ne "") { $run_parameters += " --reg_data_dir=`"$reg_dir`"" }
	$run_parameters += " --output_dir=`"$output_dir`" --output_name=`"$output_name`" --pretrained_model_name_or_path=`"$ckpt`""
	if ($is_sd_v2_ckpt -le 0) { Write-Output "Stable Diffusion 1.x чекпоинт" }
	if ($is_sd_v2_ckpt -ge 1) {
		if ($is_sd_v2_768_ckpt -ge 1) {
			$v2_resolution = "768"
			$run_parameters += " --v_parameterization"
		}
		else { $v2_resolution = "512" }
		Write-Output "Stable Diffusion 2.x ($v2_resolution) чекпоинт"
		$run_parameters += " --v2"
		if ($clip_skip -eq -not 1 -and $do_not_interrupt -le 0) {
			WCO black darkyellow 0 "Внимание: результаты обучения SD 2.x чекпоинта с clip_skip отличным от 1 могут быть непредсказуемые"
			do { $abort_script = Read-Host "Прервать выполнение скрипта? (y/N)" }
			until ($abort_script -eq "y" -or $abort_script -ceq "N")
		}
	}
	if ($vae_path -ne "") { $run_parameters += " --vae=`"$vae_path`"" }
	
	# main
	if ($desired_training_time -gt 0) { $run_parameters += " --max_train_steps=$([int]$max_train_steps)" }
	elseif ($max_train_epochs -ge 1) { $run_parameters += " --max_train_epochs=$max_train_epochs" }
	else { $run_parameters += " --max_train_steps=$max_train_steps" }
	$run_parameters += " --train_batch_size=$train_batch_size --resolution=$resolution --save_every_n_epochs=$save_every_n_epochs --save_last_n_epochs=$save_last_n_epochs"
	if ($max_token_length -eq 75) { }
	else {
		if ($max_token_length -eq 150 -or $max_token_length -eq 225) { $run_parameters += " --max_token_length=$($max_token_length)" }
		else { WCO black darkyellow 0 "Неверно указан max_token_length! Используем значение 75" } }
	$run_parameters += " --clip_skip=$clip_skip"
	
	# advanced
	if ($unet_lr -ne $learning_rate) { $run_parameters += " --unet_lr=$unet_lr" }
	if ($text_encoder_lr -ne $learning_rate) { $run_parameters += " --text_encoder_lr=$text_encoder_lr" }
	$run_parameters += " --lr_scheduler=$scheduler"
	if ($scheduler -ne "constant") {
		if ($lr_warmup_ratio -lt 0.0) { $lr_warmup_ratio = 0.0 }
		if ($lr_warmup_ratio -gt 1.0) { $lr_warmup_ratio = 1.0 }
		$lr_warmup_steps = [int]([math]::Round($max_train_steps * $lr_warmup_ratio))
		$run_parameters += " --lr_warmup_steps=$lr_warmup_steps"
	}
	$run_parameters += " --network_dim=$network_dim"
	if ($is_random_seed -le 0) { $seed = 1337 }
	else { $seed = Get-Random }
	$run_parameters += " --seed=$seed"
	if ($shuffle_caption -ge 1) { $run_parameters += " --shuffle_caption" }
	$run_parameters += " --keep_tokens=$keep_tokens"
	
	# other settings
	if ($gradient_checkpointing -ge 1) { $run_parameters += " --gradient_checkpointing"  }
	if ($gradient_accumulation_steps -gt 1) { $run_parameters += " --gradient_accumulation_steps=$gradient_accumulation_steps" }
	$run_parameters += " --max_data_loader_n_workers=$max_data_loader_n_workers"
	if ($mixed_precision -eq "fp16" -or $mixed_precision -eq "bf16") { $run_parameters += " --mixed_precision=$mixed_precision" }
	if ($save_precision -eq "float" -or $save_precision -eq "fp16" -or $save_precision -eq "bf16") { $run_parameters += " --save_precision=$save_precision" }
	if ($logging_dir -ne "") { $run_parameters += " --logging_dir=`"$logging_dir`" --log_prefix=`"$output_name`"" }
	if ($debug_dataset -ge 1) { $run_parameters += " --debug_dataset" }

	$run_parameters += " --caption_extension=`".txt`" --prior_loss_weight=1 --enable_bucket --min_bucket_reso=256 --max_bucket_reso=1024 --learning_rate=$learning_rate --use_8bit_adam --xformers --save_model_as=safetensors --cache_latents"
	
	if ($TestRun -ge 1) { $test_run = 1 }
	
	# main script
	if ($abort_script -ne "y") {
		sleep -s 0.3
		WCO black green 0 "Выполнение скрипта с параметрами:"
		sleep -s 0.3
		Write-Output "$($run_parameters -split '--' | foreach { if ($_ -ceq '') { Write-Output '' } else { Write-Output --`"$_`n`" } } | foreach { $_ -replace '=', ' = ' })"
		if ($test_run -le 0) {
			Set-Location -Path $sd_scripts_dir
			.\venv\Scripts\activate
			powershell accelerate launch --num_cpu_threads_per_process $max_data_loader_n_workers train_network.py $run_parameters
			deactivate
			Set-Location -Path $script_origin
		}
	}
} }

# chain
if ($restart -ne 1 -and $abort_script -ne "y") { foreach ($script_string in $script_paths) {
	$path = $script_string -replace "^[ \t]+|[ \t]+$"
	if ($path -ne "" -and $path -match "^(?:[a-zA-Z]:[\\\/]|\.[\\\/])(?:[^\\\/:*?`"<>|+][^^:*?`"<>|+]+[^.][\\\/])+[^:\\*?`"<>|+]+(?:[^.:\\*?`"<>|+]+)$")
	{
		if (Test-Path -Path $path -PathType "leaf") {
			if ([System.IO.Path]::GetExtension($path) -eq ".ps1") {
				if ($TestRun -ge 1) {
					Write-Output "Запускаем следующий скрипт в цепочке (тестовый режим): $path"
					powershell -ChainedRun 1 -TestRun 1 -File $path }
				else {
					Write-Output "Запускаем следующий скрипт в цепочке: $path"
					powershell -ChainedRun 1 -File $path }
			}
			else { WCO black red 0 "Ошибка: $path не является допустимым скриптом" }
		}
		else { WCO black red 0 "Ошибка: $path не является файлом" }
	}
} }

# autism2
Write-Output ""
if ($dont_draw_flags -le 0) {
$strl = 0
$version_string_length = $version_string.Length
while ($strl -lt ($([system.console]::BufferWidth))) { $strl += 1; WCO white white 1 " " }; Write-Output ""; $strl = 0; while ($version_string_length -lt $(($([system.console]::BufferWidth) + $version_string.Length) / 2)) { WCO darkblue white 1 " "; $version_string_length += 1 }; WCO darkblue white 1 $version_string; $version_string_length = $version_string.Length; while ($version_string_length -lt $(($([system.console]::BufferWidth) + $version_string.Length) / 2 - $version_string.Length % 2 + $([system.console]::BufferWidth) % 2)) { WCO darkblue white 1 " "; $version_string_length += 1 }; while ($strl -lt ($([system.console]::BufferWidth))) { $strl += 1; WCO darkred white 1 " " }
Write-Output "`n" }
sleep 3

if ($restart -eq 1) { powershell -File $PSCommandPath }

#21.01.23
#ver=1.06