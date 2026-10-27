import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser, JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CreateExpenseDto } from './dto/create-expense.dto';
import { ListExpensesQueryDto } from './dto/list-expenses-query.dto';
import {
  ExpenseListPage,
  ExpenseResponse,
  FinanceSummaryResponse,
} from './finance.mapper';
import { FinanceService } from './finance.service';

/**
 * Finance endpoints (`/v1/finance/*`): the weekly summary, the expense list
 * (typed by the user or detected by the AI in a capture, mejoras-v2 §E),
 * logging and removing an expense. All require a Bearer token; the owner
 * comes from the token.
 */
@UseGuards(JwtAuthGuard)
@Controller('finance')
export class FinanceController {
  constructor(private readonly finance: FinanceService) {}

  @Get('summary')
  summary(
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<FinanceSummaryResponse> {
    return this.finance.summary(user.id);
  }

  @Post('expenses')
  addExpense(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateExpenseDto,
  ): Promise<ExpenseResponse> {
    return this.finance.addExpense(user.id, dto);
  }

  @Get('expenses')
  listExpenses(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: ListExpensesQueryDto,
  ): Promise<ExpenseListPage> {
    return this.finance.listExpenses(user.id, query);
  }

  @Delete('expenses/:id')
  @HttpCode(204)
  removeExpense(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<void> {
    return this.finance.removeExpense(user.id, id);
  }
}
