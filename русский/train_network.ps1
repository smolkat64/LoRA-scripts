# LoRA retard-friendly train_network script v1.03 by anon
# Последнее обновление: 16.01.23 06:28 по МСК
# https://github.com/cloneofsimo/lora
# https://github.com/kohya-ss/sd-scripts
# https://rentry.org/2chAI_LoRA_Dreambooth_guide

param([int]$ChainedRun = 0, [int]$TestRun = 0)

##### Начало конфига #####

# Директории
$sd_scripts_dir = "X:\git-repos\sd-scripts\" # Путь к папке с репозиторием kohya-ss/sd-scripts
$ckpt = "X:\SD-models\checkpoint.safetensors" # Путь к чекпоинту (ckpt / safetensors)
$is_sd_v2_ckpt = 0 # Поставь '1' если загружаешь SD 2.x чекпоинт
$is_sd_v2_768_ckpt = 0 # Также поставь здесь значение '1', если загружаешь SD 2.x-768 чекпоинт
$image_dir = "X:\training_data\img" # Путь к папке с изображениями
$reg_dir = "" # Путь к папке с регуляризационными изображениями (опционально)
$output_dir = "X:\LoRA\" # Директория сохранения LoRA чекпоинтов
$output_name = "my_LoRA_network_v1" # Название файла (расширение не нужно)
$use_vae = 0 # Использовать ли VAE для загружаемого чекпоинта
$vae_path = "X:\SD-models\checkpoint.vae.pt" # Путь к VAE

# Время тренировки (опционально)
$desired_training_time = 0 # Если значение выше 0, игнорировать количество изображений с повторениями при вычислении количества шагов и обучать сеть в течении N минут.
$gpu_training_speed = "1.23it/s | 1.23s/it" # Средняя скорость тренировки, учитывая мощность GPU. Значение вида XX.XXit/s или XX.XXs/it

# Основные переменные
$train_batch_size = 1 # Количество изображений, на которых идёт обучение, одновременно. Чем больше значение, тем меньше шагов обучения (обучение проходит быстрее), но больше потребление видеопамяти
$resolution = 512 # Разрешение обучения (пиксели)
$num_epochs = 10 # Число эпох. Не имеет силы при $desired_training_time > 0
$save_every_n_epochs = 1 # Сохранять чекпоинт каждые N эпох
$save_last_n_epochs = 999 # Сохранить только последние N эпох
$max_token_length = 75 # Максимальная длина токена. Возможные значения: 75 / 150 / 225
$clip_skip = 1 # https://github.com/AUTOMATIC1111/stable-diffusion-webui/wiki/Features#ignore-last-layers-of-clip-model

# Дополнительные переменные
$learning_rate = 1e-4 # Скорость обучения
$unet_lr = $learning_rate # Скорость обучения U-Net. По умолчанию равен скорости обучения
$text_encoder_lr = $learning_rate # Скорость обучения текстового энкодера. По умолчанию равен скорости обучения
$scheduler = "cosine_with_restarts" # Планировщик скорости обучения. Возможные значения: linear, cosine, cosine_with_restarts, polynomial, constant (по умолчанию), constant_with_warmup
$lr_warmup_ratio = 0.0 # Отношение количества шагов разогрева планировщика к количеству шагов обучения (от 0 до 1)
$network_dim = 128 # Размер нетворка. Чем больше значение, тем больше точность и размер выходного файла
$save_precision = "fp16" # Использовать ли пользовательскую точность сохранения, и её тип. Возможные значения: no, float, fp16, bf16
$mixed_precision = "fp16" # Использовать ли смешанную точность для обучения, и её тип. Возможные значения: no, fp16, bf16
$is_random_seed = 1 # Сид обучения. 1 = рандомный сид, 0 = статичный
$shuffle_caption = 1 # Перетасовывать ли теги в файлах описания, разделённых запятой
$keep_tokens = 0 # Не перетасовывать первые N токенов при перемешивании описаний
$do_not_interrupt = 0 # Не прерывать работу скрипта вопросами. По умолчанию включен если выполняется цепочка скриптов.

# Последовательный запуск скриптов
# Здесь указываются пути, в которых находятся скрипты для последовательного выполнения
# Путей может быть сколько угодно
$script_paths = @(
	"<X:\Путь\к\скрипту\скрипт.ps1>",
	"<.\скрипт.ps1>",
	"<скрипт.ps1>"
)

# Остальные настройки
$test_run = 0 # Не запускать основной скрипт
$do_not_clear_host = 0 # Не очищать консоль при запуске скрипта
$logging_enabled = 0
$logging_dir = "X:\LoRA\logs\"
$log_prefix = $output_name
$debug_dataset = 0
$dont_draw_flags = 0 # Не рисовать флаги

##### Конец конфига #####

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

$current_version = "1.03"

# Аутизм №1
if ($dont_draw_flags -le 0) {
$strl = 0
$version_string = "RetardScript v$current_version"
$version_string_length = $version_string.Length
while ($strl -lt ($([system.console]::BufferWidth))) { $strl += 1; WCO white white 1 " " }; Write-Output ""; $strl = 0; while ($version_string_length -lt $(($([system.console]::BufferWidth) + $version_string.Length) / 2)) { WCO darkred white 1 " "; $version_string_length += 1 }; WCO darkred white 1 $version_string; $version_string_length = $version_string.Length; while ($version_string_length -lt $(($([system.console]::BufferWidth) + $version_string.Length) / 2 - $version_string.Length % 2 + $([system.console]::BufferWidth) % 2)) { WCO darkred white 1 " "; $version_string_length += 1 }; while ($strl -lt ($([system.console]::BufferWidth))) { $strl += 1; WCO white white 1 " " } }

Write-Output " "
Write-Output "Если что-то не работает или работает не так, писать сюда:"
WCO black blue 0 "https://github.com/anon-1337/LoRA-scripts/issues"
Write-Output " "

### Работает - не трогай, блядь!
$internet_available = 0
$script_origin = (get-location).path
Get-NetConnectionProfile | foreach { if ($_.IPv4Connectivity -eq "Internet") { $internet_available = 1 } }
sleep 3
if ((git --help) -and (curl --help) -and $internet_available -eq 1 -and -not $TestRun -ge 1 -and $ChainedRun -eq 0) {
	$script_url = "https://raw.githubusercontent.com/anon-1337/LoRA-scripts/main/%D1%80%D1%83%D1%81%D1%81%D0%BA%D0%B8%D0%B9/train_network.ps1"
	$script_github = curl --silent $script_url
	$new_version = [float]$($script_github[$script_github.Length - 1] -replace "#[a-zA-Z=]+")
	if ([float]$current_version -lt $new_version -and (Is-Numeric $new_version)) { 
		Write-Output "Доступно обновление скрипта (v$current_version => v$new_version) по адресу:"
		WCO black blue 0 $script_url
		do { $do_update = Read-Host "Выполнить обновление? (y/N)" }
		until ($do_update -eq "y" -or $do_update -ceq "N")
		if ($do_update -eq "y") {
			$restart = 1
			Set-Location -Path $script_origin
			curl --silent $script_url --output "$PSCommandPath"
			WCO black green 0 "Обновлено до версии v$new_version!"
			Write-Output "Перезапуск..."
			sleep 2 }
	}
}
###

if ($restart -ne 1) {

function Word-Ending($value) {
	$ending = $value.ToString()
	if ($ending -ge "11" -and $ending -le "19") { return "й" }
	$ending = $ending.Substring([Math]::Max($ending.Length, 0) - 1)
	if ($ending -eq "1") { return "е" }
	if ($ending -ge "2" -and $ending -le "4") { return "я" }
	if (($ending -ge "5" -and $ending -le "9") -or $ending -eq "0") { return "й" } }

Write-Output "Подсчет количества изображений в папках"
$total = 0
$is_structure_wrong = 0
$abort_script = 0
$iter = 0

if ($is_chained_run -ge 1) { $do_not_interrupt = 1 }

Get-ChildItem -Path $image_dir -Directory | ForEach-Object {
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
}

$iter = 0

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
	if ($do_not_interrupt -le 0) {
		if ($reg_imgs -eq 0) {
			WCO black darkyellow 0 "Внимание: папка для регуляризационных изображений присутствует, но в ней ничего нет"
			do { $abort_script = Read-Host "Прервать выполнение скрипта? (y/N)" }
			until ($abort_script -eq "y" -or $abort_script -ceq "N")
			return }
		else {
			$img_repeats = ($repeats * $reg_imgs)
			Write-Output "`t$($parts[1]): $repeats повторени$(Word-Ending $repeats) * $reg_imgs изображени$(Word-Ending $reg_imgs) = $($img_repeats)"
			$iter += 1 }
	}
} } } }

if ($is_structure_wrong -eq 0 -and $abort_script -ne "y")
{
	Write-Output "Количество обучающих изображений с повторениями: $total"
	if ($desired_training_time -gt 0) 
	{
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
					Write-Output "Количество шагов: $([math]::Round($($speed_value * 60), 2)) it/min * $desired_training_time минут(-а) ≈ $max_train_steps шаг(-ов)" }
				else {
					Write-Output "Вы выбрали нет. Увеличенное время компенсировано не будет, длительность тренировки увеличена вдвое"
					Write-Output "Количество шагов: $([math]::Round($($speed_value * 60), 2)) it/min * $desired_training_time минут(-а) * 2 ≈ $max_train_steps шаг(-ов)" }
			}
			else {
				$max_train_steps = [int]([math]::Round($max_train_steps))
				Write-Output "Количество шагов: $([math]::Round($($speed_value * 60), 2)) it/min * $desired_training_time минут(-а) ≈ $max_train_steps training шаг(-ов)" }
		}
		else {
			WCO black red 0 "Неверно указана скорость обучения gpu_training_speed!"
			$abort_script = "y" }
	}
	else
	{
		Write-Output "Используем количество изображений для вычисления шагов обучения"
		Write-Output "Количество эпох: $num_epochs"
		Write-Output "Размер обучающей партии (train_batch_size): $train_batch_size"
		if ($reg_imgs -gt 0)
		{
			$total *= 2
			Write-Output "Количество регуляризационных изображений больше 0: количество шагов будет увеличено вдвое"
		}
		$max_train_steps = [int]($total / $train_batch_size * $num_epochs)
		Write-Output "Количество шагов: $total / $train_batch_size * $num_epochs = $max_train_steps"
	}
	
	if ($is_random_seed -le 0) { $seed = 1337 }
	else { $seed = Get-Random }
	
	if ($lr_warmup_ratio -lt 0.0) { $lr_warmup_ratio = 0.0 }
	if ($lr_warmup_ratio -gt 1.0) { $lr_warmup_ratio = 1.0 }
	$lr_warmup_steps = [int]([math]::Round($max_train_steps * $lr_warmup_ratio))
	
	$image_dir = $image_dir.TrimEnd("\", "/")
	$reg_dir = $reg_dir.TrimEnd("\", "/")
	$output_dir = $output_dir.TrimEnd("\", "/")
	$logging_dir = $logging_dir.TrimEnd("\", "/")
	
	$run_parameters = "--network_module=networks.lora --pretrained_model_name_or_path=`"$ckpt`" --train_data_dir=`"$image_dir`" --output_dir=`"$output_dir`" --output_name=`"$output_name`" --caption_extension=`".txt`" --resolution=$resolution --prior_loss_weight=1 --enable_bucket --min_bucket_reso=256 --max_bucket_reso=1024 --train_batch_size=$train_batch_size --lr_warmup_steps=$lr_warmup_steps --learning_rate=$learning_rate --unet_lr=$unet_lr --text_encoder_lr=$text_encoder_lr --max_train_steps=$([int]$max_train_steps) --use_8bit_adam --xformers --save_every_n_epochs=$save_every_n_epochs --save_last_n_epochs=$save_last_n_epochs --save_model_as=safetensors --keep_tokens=$keep_tokens --clip_skip=$clip_skip --seed=$seed --network_dim=$network_dim --cache_latents --lr_scheduler=$scheduler"
	
	if ($reg_dir -ne "") { $run_parameters += " --reg_data_dir=`"$reg_dir`"" }
	
	if ($max_token_length -eq 75) { }
	else {
		if ($max_token_length -eq 150 -or $max_token_length -eq 225) { $run_parameters += " --max_token_length=$($max_token_length)" }
		else { WCO black darkyellow 0 "Неверно указан max_token_length! Используем значение 75" } }
	
	if ($shuffle_caption -ge 1) { $run_parameters += " --shuffle_caption" }
	if ($logging_enabled -ge 1) { $run_parameters += " --logging_dir=`"$logging_dir`" --log_prefix=`"$output_name`""}
	if ($use_vae -ge 1) { $run_parameters += " --vae=`"$vae_path`"" }
	if ($mixed_precision -eq "fp16" -or $mixed_precision -eq "bf16") { $run_parameters += " --mixed_precision=$mixed_precision" }
	if ($save_precision -eq "float" -or $save_precision -eq "fp16" -or $save_precision -eq "bf16") { $run_parameters += " --save_precision=$save_precision" }
	if ($debug_dataset -ge 1) { $run_parameters += " --debug_dataset"}
	
	if ($abort_script -ne "y")
	{
		if ($is_sd_v2_ckpt -le 0) { Write-Output "Stable Diffusion 1.x чекпоинт" }
		if ($is_sd_v2_ckpt -ge 1)
		{
			if ($is_sd_v2_768_ckpt -ge 1)
			{
				$v2_resolution = "768"
				$run_parameters += " --v_parameterization"
			}
			else { $v2_resolution = "512" }
			Write-Output "Stable Diffusion 2.x ($v2_resolution) чекпоинт"
			$run_parameters += " --v2"
			if ($clip_skip -eq -not 1 -and $do_not_interrupt -le 0)
			{
				WCO black darkyellow 0 "Внимание: результаты обучения SD 2.x чекпоинта с clip_skip отличным от 1 могут быть непредсказуемые"
				do { $abort_script = Read-Host "Прервать выполнение скрипта? (y/N)" }
				until ($abort_script -eq "y" -or $abort_script -ceq "N")
			}
		}
	}
	
	if ($TestRun -ge 1) { $test_run = 1 }
	
	if ($abort_script -ne "y")
	{
		sleep -s 0.3
		WCO black green 0 "Выполнение скрипта с параметрами:"
		sleep -s 0.3
		Write-Output "$($run_parameters -split '--' | foreach { if ($_ -ceq '') { Write-Output '' } else { Write-Output --`"$_`n`" } } | foreach { $_ -replace '=', ' = ' })"
		if ($test_run -le 0)
		{
			Set-Location -Path $sd_scripts_dir
			.\venv\Scripts\activate
			powershell accelerate launch --num_cpu_threads_per_process 12 train_network.py $run_parameters
			deactivate
			Set-Location -Path $script_origin
		}
	}
} }

if ($restart -ne 1 -and $abort_script -ne "y") { foreach ($script_string in $script_paths) {
	$path = $script_string -replace "^[ \t]+|[ \t]+$"
	if ($path -ne "" -and $path -match "^(?:[a-zA-Z]:[\\\/]|\.[\\\/])(?:[^\\\/:*?`"<>|+][^^:*?`"<>|+]+[^.][\\\/])+[^:\\*?`"<>|+]+(?:[^.:\\*?`"<>|+]+)$")
	{
		if (Test-Path -Path $path -PathType "leaf") {
			if ([System.IO.Path]::GetExtension($path) -eq ".ps1") {
				if ($TestRun -ge 1) {
					Write-Output "Запускаем следующий скрипт в цепочке (тестовый режим): $path"
					powershell -File $path -ChainedRun 1 -TestRun 1 }
				else {
					Write-Output "Запускаем следующий скрипт в цепочке: $path"
					powershell -File $path -ChainedRun 1 }
			}
			else { WCO black red 0 "Ошибка: $path не является допустимым скриптом" }
		}
		else { WCO black red 0 "Ошибка: $path не является файлом" }
	}
} }

# Аутизм №2
Write-Output ""
if ($dont_draw_flags -le 0) {
$strl = 0
$version_string_length = $version_string.Length
while ($strl -lt ($([system.console]::BufferWidth))) { $strl += 1; WCO white white 1 " " }; Write-Output ""; $strl = 0; while ($version_string_length -lt $(($([system.console]::BufferWidth) + $version_string.Length) / 2)) { WCO darkblue white 1 " "; $version_string_length += 1 }; WCO darkblue white 1 $version_string; $version_string_length = $version_string.Length; while ($version_string_length -lt $(($([system.console]::BufferWidth) + $version_string.Length) / 2 - $version_string.Length % 2 + $([system.console]::BufferWidth) % 2)) { WCO darkblue white 1 " "; $version_string_length += 1 }; while ($strl -lt ($([system.console]::BufferWidth))) { $strl += 1; WCO darkred white 1 " " }
Write-Output "`n" }

sleep 3

if ($restart -eq 1) { powershell -File $PSCommandPath }

#ver=1.03